[CmdletBinding()]
param(
    [string]$ModulePath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'EndpointForge.psd1'
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
if (-not (Test-Path -LiteralPath $resolvedModulePath -PathType Leaf)) {
    throw "EndpointForge manifest '$resolvedModulePath' was not found."
}
Import-Module $resolvedModulePath -Force

$softwareCount = @(Get-EFInstalledSoftware -Scope CurrentUser).Count
try {
    $summary = Get-EFEndpointSummary -NoProgress
    $inventory = $summary.Inventory
    $pending = $summary.Health.PendingReboot
    $compliance = $summary.Compliance
}
catch {
    Write-Error ("Summary runtime smoke test failed: {0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
    throw
}
$shownSummary = $summary | Show-EFEndpointSummary -NoColor -PassThru
$plan = Get-EFRemediationPlan -NoProgress
$managementAgentHealth = @(Get-EFManagementAgentHealth -Agent All -TimeoutSeconds 5)
if ($managementAgentHealth.Count -ne 2 -or
    @($managementAgentHealth | Where-Object { $_.LocalStatus -notin @('LooksReady', 'NeedsAttention', 'NotDetected', 'CouldNotCheck') }).Count -ne 0 -or
    @($managementAgentHealth | Where-Object { $_.NetworkActivityPerformed -or -not $_.SensitiveDataIncluded }).Count -ne 0) {
    throw 'The local management-agent health smoke test did not return two safe structured results.'
}
$managementAgentPreviews = @(
    Invoke-EFManagementAgentAction -Agent Intune -Action RestartAgentService -WhatIf -Confirm:$false
    Invoke-EFManagementAgentAction -Agent ConfigurationManager -Action RequestMachinePolicy -WhatIf -Confirm:$false
)
if ($managementAgentPreviews.Count -ne 2 -or
    @($managementAgentPreviews | Where-Object { $_.Outcome -ne 'WhatIf' -or $_.ChangeMayHaveOccurred }).Count -ne 0) {
    throw 'The management-agent action WhatIf guard failed.'
}
$booleanCompliance = Test-EFEndpointCompliance -NoProgress
if ($booleanCompliance -isnot [bool]) {
    throw 'Test-EFEndpointCompliance did not return a Boolean.'
}
if ($shownSummary.CorrelationId -ne $summary.CorrelationId) {
    throw 'Show-EFEndpointSummary PassThru did not preserve the input summary.'
}

$cimNamespaceBaseline = [pscustomobject]@{
    Name = 'Runtime.CimNamespace'
    Version = '1.0.0'
    Description = 'Runtime local WMI namespace check.'
    Controls = @(
        [pscustomobject]@{
            Id = 'RUNTIME-CIMV2'; Title = 'Core Windows management information';
            Type = 'CimNamespaceExists'; Severity = 'High'; Namespace = 'root\cimv2';
            TimeoutSeconds = 10; DesiredValue = $true; Remediable = $false; RequiresReboot = $false
        }
    )
}
$cimNamespaceReport = Get-EFComplianceReport -Baseline $cimNamespaceBaseline -NoProgress
if (-not $cimNamespaceReport.IsCompliant -or $cimNamespaceReport.Results[0].ActualValue -isnot [bool]) {
    throw 'The local root\cimv2 namespace runtime check did not return a passing Boolean result.'
}

$ipRangeBaseline = [pscustomobject]@{
    Name = 'Runtime.IpRange'
    Version = '1.0.0'
    Description = 'Runtime local IP range check without network contact.'
    Controls = @(
        [pscustomobject]@{
            Id = 'RUNTIME-IP-RANGE'; Title = 'An active local address can be evaluated';
            Type = 'IpAddressInRange'; Severity = 'Medium';
            ApprovedRanges = @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1');
            TimeoutSeconds = 10; DesiredValue = $true; Remediable = $false;
            RequiresReboot = $false
        }
    )
}
$ipRangeReport = Get-EFComplianceReport -Baseline $ipRangeBaseline -NoProgress
if (-not $ipRangeReport.IsCompliant -or $ipRangeReport.Results[0].ActualValue -isnot [bool]) {
    throw 'The local IP range runtime check did not return a passing Boolean result.'
}

$whatIfKey = "HKCU:\Software\EndpointForgeRuntimeSmoke-$([guid]::NewGuid().ToString('N'))"
$previewBaseline = [pscustomobject]@{
    Name = 'Runtime.WhatIf'
    Version = '1.0.0'
    Description = 'Runtime WhatIf safety check.'
    Controls = @(
        [pscustomobject]@{
            Id = 'RUNTIME-WHATIF'; Title = 'WhatIf guard'; Type = 'Registry'; Severity = 'Low'
            Path = $whatIfKey; ValueName = 'Expected'; ValueType = 'DWord'; DesiredValue = 1
            Remediable = $true; RequiresReboot = $false
        }
    )
}
$preview = Invoke-EFEndpointRemediation -Baseline $previewBaseline -WhatIf
if ($preview.Results[0].Outcome -ne 'WhatIf' -or (Test-Path -LiteralPath $whatIfKey)) {
    throw 'Remediation WhatIf guard failed.'
}

if ([string]::IsNullOrWhiteSpace([string]$inventory.ComputerName)) {
    throw 'Inventory did not return a computer name.'
}
if (@($compliance.Results).Count -ne @((Get-EFBaseline).Controls).Count) {
    throw 'Compliance did not return one result per built-in control.'
}

[pscustomobject]@{
    PendingReboot      = $pending.IsRebootPending
    CurrentUserSoftware = $softwareCount
    InventoryComputer  = $inventory.ComputerName
    InventoryErrors    = @($inventory.Errors).Count
    Baseline           = $compliance.BaselineName
    ComplianceScore    = $compliance.Score
    ComplianceExitCode = $compliance.ExitCode
    ControlErrors      = $compliance.ErrorCount
    CimNamespaceStatus = $cimNamespaceReport.Results[0].Status
    IpRangeStatus      = $ipRangeReport.Results[0].Status
    SummaryStatus      = $summary.OverallStatus
    SummaryDataStatus  = $summary.DataStatus
    PlanCandidates     = $plan.CandidateCount
    PlanBlocked        = $plan.BlockedCount
    ManagementAgents   = $managementAgentHealth.Count
    ManagementPreviews = $managementAgentPreviews.Count
}

if (@($inventory.Errors).Count -gt 0) {
    Write-Output 'Inventory capability notes:'
    $inventory.Errors | ForEach-Object { Write-Output "  $_" }
}

$compliance.Results | Format-Table ControlId, Status, Message -Wrap -AutoSize
