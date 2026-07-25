[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Unmanaged', 'Intune', 'ConfigurationManager', 'CoManaged')]
    [string]$Ring,

    [string]$ModulePath,

    [string]$OutputPath,

    [switch]$AllowChangingActions,

    [string]$ChangeAcknowledgement
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'EndpointForge.psd1'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot "TestResults\managed-endpoint-$($Ring.ToLowerInvariant()).json"
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

if ($AllowChangingActions -and $ChangeAcknowledgement -cne 'I_ACCEPT_MANAGED_ENDPOINT_CHANGES') {
    throw 'Changing certification actions require the exact ChangeAcknowledgement value I_ACCEPT_MANAGED_ENDPOINT_CHANGES.'
}

Import-Module $resolvedModulePath -Force -ErrorAction Stop
$startedAtUtc = [DateTime]::UtcNow
$errors = [Collections.Generic.List[string]]::new()
$runtimePassed = $false
try {
    & (Join-Path $PSScriptRoot 'Test-WindowsRuntime.ps1') -ModulePath $resolvedModulePath
    $runtimePassed = $true
}
catch {
    $errors.Add('The Windows runtime smoke test failed.')
}

$health = @()
try {
    $health = @(Get-EFManagementAgentHealth -Agent All -TimeoutSeconds 15)
}
catch {
    $errors.Add('Management-agent health could not be collected.')
}

$intuneHealth = @($health | Where-Object Agent -eq 'Intune' | Select-Object -First 1)
$configMgrHealth = @($health | Where-Object Agent -eq 'ConfigurationManager' | Select-Object -First 1)
$expectIntune = $Ring -in @('Intune', 'CoManaged')
$expectConfigMgr = $Ring -in @('ConfigurationManager', 'CoManaged')
if ($intuneHealth.Count -ne 1 -or [bool]$intuneHealth[0].Installed -ne $expectIntune) {
    $errors.Add("The Intune agent presence did not match the '$Ring' certification ring.")
}
elseif (($expectIntune -and [string]$intuneHealth[0].LocalStatus -ne 'LooksReady') -or
    (-not $expectIntune -and [string]$intuneHealth[0].LocalStatus -ne 'NotDetected')) {
    $errors.Add("The Intune local status did not provide complete healthy evidence for the '$Ring' certification ring.")
}
if ($configMgrHealth.Count -ne 1 -or [bool]$configMgrHealth[0].Installed -ne $expectConfigMgr) {
    $errors.Add("The Configuration Manager agent presence did not match the '$Ring' certification ring.")
}
elseif (($expectConfigMgr -and [string]$configMgrHealth[0].LocalStatus -ne 'LooksReady') -or
    (-not $expectConfigMgr -and [string]$configMgrHealth[0].LocalStatus -ne 'NotDetected')) {
    $errors.Add("The Configuration Manager local status did not provide complete healthy evidence for the '$Ring' certification ring.")
}

$previewResults = [Collections.Generic.List[object]]::new()
foreach ($previewDefinition in @(
    @{ Agent = 'Intune'; Action = 'RestartAgentService' },
    @{ Agent = 'ConfigurationManager'; Action = 'RequestMachinePolicy' }
)) {
    try {
        $preview = Invoke-EFManagementAgentAction -Agent $previewDefinition.Agent `
            -Action $previewDefinition.Action -WhatIf -Confirm:$false
        $previewResults.Add([pscustomobject][ordered]@{
            Agent                   = $preview.Agent
            Action                  = $preview.Action
            Outcome                 = $preview.Outcome
            ChangeMayHaveOccurred   = [bool]$preview.ChangeMayHaveOccurred
            NetworkActivityAllowed  = [bool]$preview.NetworkActivityAllowed
        })
        if ($preview.Outcome -ne 'WhatIf' -or $preview.ChangeMayHaveOccurred) {
            $errors.Add("The $($preview.Agent) WhatIf preview did not preserve the no-change guarantee.")
        }
    }
    catch {
        $errors.Add("The $($previewDefinition.Agent) action preview failed.")
    }
}

$changingResults = [Collections.Generic.List[object]]::new()
if ($AllowChangingActions) {
    $isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdministrator) {
        $errors.Add('Changing certification actions require an Administrator session.')
    }
    else {
        $approvedActions = [Collections.Generic.List[object]]::new()
        if ($expectIntune) {
            $approvedActions.Add(@{ Agent = 'Intune'; Action = 'RestartAgentService' })
        }
        if ($expectConfigMgr) {
            $approvedActions.Add(@{ Agent = 'ConfigurationManager'; Action = 'RequestMachinePolicy' })
        }
        foreach ($actionDefinition in $approvedActions) {
            try {
                $actionResult = Invoke-EFManagementAgentAction -Agent $actionDefinition.Agent `
                    -Action $actionDefinition.Action -AllowManagementTraffic -TimeoutSeconds 60 -Confirm:$false
                $changingResults.Add([pscustomobject][ordered]@{
                    Agent                  = $actionResult.Agent
                    Action                 = $actionResult.Action
                    Outcome                = $actionResult.Outcome
                    IsSuccessful           = [bool]$actionResult.IsSuccessful
                    ChangeMayHaveOccurred  = [bool]$actionResult.ChangeMayHaveOccurred
                    RequestAccepted        = [bool]$actionResult.RequestAccepted
                    ImmediateEffectVerified = [bool]$actionResult.ImmediateEffectVerified
                })
                if (-not $actionResult.IsSuccessful) {
                    $errors.Add("The approved $($actionResult.Agent) certification action did not succeed.")
                }
            }
            catch {
                $errors.Add("The approved $($actionDefinition.Agent) certification action failed.")
            }
        }
    }
}

$operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
$module = Get-Module EndpointForge -ErrorAction Stop
$report = [pscustomobject][ordered]@{
    EvidenceVersion          = '1.0'
    Ring                     = $Ring
    ModuleVersion            = $module.Version.ToString()
    StartedAtUtc             = $startedAtUtc
    CompletedAtUtc           = [DateTime]::UtcNow
    WindowsCaption           = [string]$operatingSystem.Caption
    WindowsVersion           = [string]$operatingSystem.Version
    WindowsBuild             = [string]$operatingSystem.BuildNumber
    Architecture             = [string]$operatingSystem.OSArchitecture
    PowerShellEdition        = [string]$PSVersionTable.PSEdition
    PowerShellVersion        = $PSVersionTable.PSVersion.ToString()
    ExecutionIdentity        = if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        'SYSTEM'
    }
    elseif (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        'Administrator'
    }
    else {
        'StandardUser'
    }
    RuntimeSmokePassed       = $runtimePassed
    IntuneExpected           = $expectIntune
    IntuneDetected           = if ($intuneHealth.Count -eq 1) { [bool]$intuneHealth[0].Installed } else { $null }
    IntuneLocalStatus        = if ($intuneHealth.Count -eq 1) { [string]$intuneHealth[0].LocalStatus } else { 'CouldNotCheck' }
    ConfigurationManagerExpected = $expectConfigMgr
    ConfigurationManagerDetected = if ($configMgrHealth.Count -eq 1) { [bool]$configMgrHealth[0].Installed } else { $null }
    ConfigurationManagerLocalStatus = if ($configMgrHealth.Count -eq 1) { [string]$configMgrHealth[0].LocalStatus } else { 'CouldNotCheck' }
    WhatIfResults            = $previewResults.ToArray()
    ChangingActionsRequested = [bool]$AllowChangingActions
    ChangingActionResults    = $changingResults.ToArray()
    Passed                   = $errors.Count -eq 0
    ErrorCount               = $errors.Count
    Errors                   = $errors.ToArray()
    Privacy                  = 'Computer name, user name, IP addresses, agent version, log paths, and log contents are intentionally omitted.'
}

$outputParent = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outputParent -Force
}
[IO.File]::WriteAllText(
    $resolvedOutputPath,
    ($report | ConvertTo-Json -Depth 8),
    [Text.UTF8Encoding]::new($false)
)

$report
if (-not $report.Passed) {
    throw "Managed-endpoint certification failed with $($report.ErrorCount) finding(s). See '$resolvedOutputPath'."
}
