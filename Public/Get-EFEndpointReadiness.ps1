function Get-EFEndpointReadiness {
    <#
    .SYNOPSIS
    Explains what EndpointForge can check and safely offer to fix in the current PowerShell window.

    .DESCRIPTION
    Performs a non-changing preflight. It checks the Windows platform, the selected
    checklist, administrator access, remote-session context, and whether Windows provides
    the features needed by each checklist item. It does not run the checklist. It
    identifies network-active items because running them later can contact a named server,
    name-resolution service, web address, configured Windows Update service, or identity
    provider while resolving a requested local-group account name.

    EndpointForge calls its list of expected settings a baseline. In user-friendly
    guidance, this command calls it a checklist: a list of things expected to be true,
    including settings, updates, storage, applications, jobs, files, certificates, events,
    account relationships, or network availability. Selecting a checklist does not run it
    or apply it.

    .PARAMETER Baseline
    The checklist to inspect. Supply the built-in name, a custom JSON path, or a validated
    checklist object. The default is the conservative EnterpriseRecommended checklist.

    .PARAMETER ControlId
    Limits readiness discovery to specific checklist item identifiers.

    .EXAMPLE
    Get-EFEndpointReadiness

    .EXAMPLE
    Get-EFEndpointReadiness -Baseline .\Contoso.Workstation.json

    .OUTPUTS
    EndpointForge.EndpointReadiness

    .LINK
    Get-EFEndpointSummary

    .LINK
    Get-EFRemediationPlan
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [string[]]$ControlId
    )

    $checkedAtUtc = [DateTime]::UtcNow
    $isWindowsPlatform = [bool](Test-EFWindows)
    $isAdministrator = $false
    if ($isWindowsPlatform) {
        $isAdministrator = [bool](Test-EFAdministrator)
    }

    $isRemoteSession = $false
    try {
        $senderInfo = Get-Variable -Name PSSenderInfo -ValueOnly -ErrorAction SilentlyContinue
        $isRemoteSession = $null -ne $senderInfo
    }
    catch {
        $isRemoteSession = $false
    }

    $resolvedBaseline = $null
    $baselineError = $null
    [object[]]$controls = @()
    try {
        $resolvedBaseline = Resolve-EFBaseline -Baseline $Baseline
        $controls = @($resolvedBaseline.Controls)
        if ($PSBoundParameters.ContainsKey('ControlId') -and $null -ne $ControlId -and $ControlId.Count -gt 0) {
            $missingIds = @($ControlId | Where-Object { $_ -notin $controls.Id })
            if ($missingIds.Count -gt 0) {
                throw [System.ArgumentException]::new("The checklist does not contain item(s): $($missingIds -join ', ').")
            }
            $controls = @($controls | Where-Object { $_.Id -in @($ControlId) })
        }
    }
    catch {
        $baselineError = $_.Exception.Message
        $resolvedBaseline = $null
        $controls = @()
    }

    $baselineIsValid = $null -ne $resolvedBaseline
    $checklistName = if ($baselineIsValid) { [string]$resolvedBaseline.Name } else { 'Unavailable' }
    $checklistVersion = if ($baselineIsValid) { [string]$resolvedBaseline.Version } else { $null }
    $capabilities = @(
        foreach ($control in $controls) {
            Get-EFControlCapability -Control $control -IsWindowsPlatform $isWindowsPlatform -IsAdministrator $isAdministrator
        }
    )

    $unavailableControlCount = @($capabilities | Where-Object { -not $_.CanCheck }).Count
    $privilegedCheckCount = @($capabilities | Where-Object AdministratorRecommendedForCheck).Count
    $automaticFixCount = @($capabilities | Where-Object IsAutomaticFixDeclared).Count
    $availableAutomaticFixCount = @($capabilities | Where-Object AutomaticFixAvailable).Count
    $fixNowCount = @($capabilities | Where-Object CanFixNow).Count
    $networkCheckCount = @($controls | Where-Object { Test-EFControlUsesNetwork -Control $_ }).Count

    $assessmentReady = $isWindowsPlatform -and $baselineIsValid
    $completeCheckLikely = $assessmentReady -and $unavailableControlCount -eq 0 -and
        ($isAdministrator -or $privilegedCheckCount -eq 0)
    $fixReady = $assessmentReady -and $isAdministrator -and $availableAutomaticFixCount -gt 0

    $limitations = [Collections.Generic.List[string]]::new()
    if (-not $isWindowsPlatform) {
        $limitations.Add('Endpoint checks require Windows 10, Windows 11, or a supported Windows Server release.')
    }
    if (-not $baselineIsValid) {
        $limitations.Add("The selected checklist could not be used: $baselineError")
    }
    if ($assessmentReady -and -not $isAdministrator -and $privilegedCheckCount -gt 0) {
        $limitations.Add("Windows may hide details for $privilegedCheckCount checklist item(s) until PowerShell is opened using Run as administrator.")
    }
    if ($assessmentReady -and -not $isAdministrator -and $automaticFixCount -gt 0) {
        $limitations.Add('This standard-user PowerShell window can check settings, but it cannot apply automatic fixes.')
    }
    if ($unavailableControlCount -gt 0) {
        $limitations.Add("Windows features needed by $unavailableControlCount checklist item(s) are unavailable in this session.")
    }
    if ($isRemoteSession) {
        $limitations.Add('This is a remote PowerShell session. Checks and approved fixes affect the remote PC, not the PC in front of you.')
    }
    if ($networkCheckCount -gt 0) {
        $limitations.Add(
            "$networkCheckCount checklist item(s) can contact an approved TCP destination, DNS service, web address, or configured update service when run. Those systems or network monitoring tools may record the activity."
        )
    }

    $status = if (-not $assessmentReady) {
        'Blocked'
    }
    elseif (-not $completeCheckLikely -or ($automaticFixCount -gt 0 -and -not $isAdministrator) -or
        $availableAutomaticFixCount -lt $automaticFixCount) {
        'Limited'
    }
    else {
        'Ready'
    }

    $summary = switch ($status) {
        'Blocked' { 'EndpointForge cannot start this checklist until the blocked item is corrected.' }
        'Limited' { 'EndpointForge can check this PC now, but some details or automatic fixes may be unavailable.' }
        default { 'EndpointForge is ready to check this PC. The check does not change Windows; review the Network activity line before allowing any network-active items.' }
    }
    $nextStep = if (-not $isWindowsPlatform) {
        'Run EndpointForge on the Windows PC you want to check.'
    }
    elseif (-not $baselineIsValid) {
        'Choose the built-in recommended checklist or correct the custom checklist file, then run readiness again.'
    }
    elseif (-not $isAdministrator -and ($privilegedCheckCount -gt 0 -or $automaticFixCount -gt 0)) {
        'You can run a check now. For the most complete result, reopen PowerShell using Run as administrator and check again.'
    }
    elseif ($unavailableControlCount -gt 0) {
        'Run the check and review unavailable items. They may not apply to this Windows edition or device type.'
    }
    else {
        'Run Get-EFEndpointSummary, or choose Check this PC from the guided menu.'
    }

    $checks = [Collections.Generic.List[object]]::new()
    $checks.Add([pscustomobject]@{
        PSTypeName = 'EndpointForge.ReadinessCheck'
        Name = 'Windows PC'
        Status = if ($isWindowsPlatform) { 'Ready' } else { 'Blocked' }
        PlainLanguage = if ($isWindowsPlatform) { 'This PowerShell window is running on Windows.' } else { 'EndpointForge endpoint checks must run on Windows.' }
        NextStep = if ($isWindowsPlatform) { 'No action is needed.' } else { 'Open PowerShell on the Windows PC you want to check.' }
    })
    $checks.Add([pscustomobject]@{
        PSTypeName = 'EndpointForge.ReadinessCheck'
        Name = 'Checklist'
        Status = if ($baselineIsValid) { 'Ready' } else { 'Blocked' }
        PlainLanguage = if ($baselineIsValid) {
            "'$checklistName' is valid and contains $($controls.Count) item(s). A checklist is a list of things expected to be true; selecting it does not run checks or apply changes."
        }
        else {
            "The selected checklist could not be read or validated: $baselineError"
        }
        NextStep = if ($baselineIsValid) { 'No action is needed.' } else { 'Choose a valid built-in checklist or custom JSON checklist file.' }
    })
    $checks.Add([pscustomobject]@{
        PSTypeName = 'EndpointForge.ReadinessCheck'
        Name = 'PowerShell access'
        Status = if ($isAdministrator) { 'Ready' } elseif ($assessmentReady) { 'Warning' } else { 'Blocked' }
        PlainLanguage = if ($isAdministrator) {
            'PowerShell is running as Administrator. Complete checks and guarded fixes can be offered when Windows supports them.'
        }
        else {
            'PowerShell is running as a standard user. Normal checks work, but Windows may hide protected details and EndpointForge will not apply fixes.'
        }
        NextStep = if ($isAdministrator) { 'No action is needed.' } else { 'Check now, or use Run as administrator if you need complete protected details or later approve a fix.' }
    })
    $checks.Add([pscustomobject]@{
        PSTypeName = 'EndpointForge.ReadinessCheck'
        Name = 'Windows features'
        Status = if (-not $assessmentReady) { 'Blocked' } elseif ($unavailableControlCount -gt 0) { 'Warning' } else { 'Ready' }
        PlainLanguage = if (-not $assessmentReady) {
            'Windows feature discovery will begin after the platform and checklist are ready.'
        }
        elseif ($unavailableControlCount -gt 0) {
            "$unavailableControlCount checklist item(s) need a Windows feature that is unavailable in this session. EndpointForge will report those items instead of guessing."
        }
        else {
            'The Windows commands needed by every selected checklist item are available.'
        }
        NextStep = if ($unavailableControlCount -gt 0) { 'Review ControlCapabilities for the exact unavailable feature.' } else { 'No action is needed.' }
    })
    $checks.Add([pscustomobject]@{
        PSTypeName = 'EndpointForge.ReadinessCheck'
        Name = 'Network activity'
        Status = if ($networkCheckCount -gt 0) { 'Warning' } elseif ($assessmentReady) { 'Ready' } else { 'Blocked' }
        PlainLanguage = if ($networkCheckCount -gt 0) {
            "$networkCheckCount checklist item(s) can contact a named TCP destination, DNS service, web address, configured update service, or identity provider for the requested account when the checklist is run. The activity may be recorded."
        }
        elseif ($assessmentReady) {
            'This checklist does not contain network-active checks.'
        }
        else {
            'Network activity can be described after the checklist is ready.'
        }
        NextStep = if ($networkCheckCount -gt 0) { 'Review every network-active item and confirm that its destination, requested identity, and purpose are approved.' } else { 'No action is needed.' }
    })
    $checks.Add([pscustomobject]@{
        PSTypeName = 'EndpointForge.ReadinessCheck'
        Name = 'Target PC'
        Status = if ($isRemoteSession) { 'Warning' } else { 'Ready' }
        PlainLanguage = if ($isRemoteSession) {
            'This PowerShell window is connected to another PC. Every check and approved fix affects that remote PC.'
        }
        else {
            'This PowerShell window is checking the local PC.'
        }
        NextStep = if ($isRemoteSession) { 'Confirm the remote computer name before approving any future change.' } else { 'No action is needed.' }
    })

    [pscustomobject]@{
        PSTypeName                    = 'EndpointForge.EndpointReadiness'
        ComputerName                  = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { [Environment]::MachineName } else { $env:COMPUTERNAME }
        CheckedAtUtc                  = $checkedAtUtc
        Status                        = $status
        AssessmentReady               = $assessmentReady
        CompleteCheckLikely           = $completeCheckLikely
        FixReady                      = $fixReady
        IsWindows                     = $isWindowsPlatform
        IsAdministrator               = $isAdministrator
        IsRemoteSession               = $isRemoteSession
        ChecklistName                 = $checklistName
        ChecklistVersion              = $checklistVersion
        ChecklistDefinition           = 'A checklist (called a baseline in automation) is a list of things expected to be true, such as settings, files, recent events, and network availability. Selecting it does not run checks or apply changes.'
        ControlCount                  = $controls.Count
        AvailableControlCount         = $capabilities.Count - $unavailableControlCount
        UnavailableControlCount       = $unavailableControlCount
        PrivilegedCheckCount          = $privilegedCheckCount
        AutomaticFixCount             = $automaticFixCount
        AvailableAutomaticFixCount    = $availableAutomaticFixCount
        FixNowCount                   = $fixNowCount
        NetworkCheckCount             = $networkCheckCount
        Summary                       = $summary
        NextStep                      = $nextStep
        Limitations                   = @($limitations)
        Checks                        = @($checks)
        ControlCapabilities           = @($capabilities)
    }
}
