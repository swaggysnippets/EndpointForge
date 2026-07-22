[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'EndpointForge.psd1') -Force

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
$booleanCompliance = Test-EFEndpointCompliance -NoProgress
if ($booleanCompliance -isnot [bool]) {
    throw 'Test-EFEndpointCompliance did not return a Boolean.'
}
if ($shownSummary.CorrelationId -ne $summary.CorrelationId) {
    throw 'Show-EFEndpointSummary PassThru did not preserve the input summary.'
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
    SummaryStatus      = $summary.OverallStatus
    SummaryDataStatus  = $summary.DataStatus
    PlanCandidates     = $plan.CandidateCount
    PlanBlocked        = $plan.BlockedCount
}

if (@($inventory.Errors).Count -gt 0) {
    Write-Output 'Inventory capability notes:'
    $inventory.Errors | ForEach-Object { Write-Output "  $_" }
}

$compliance.Results | Format-Table ControlId, Status, Message -Wrap -AutoSize
