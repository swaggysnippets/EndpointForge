<#
.SYNOPSIS
Runs a read-only computer check, or applies explicitly approved checklist items.

.DESCRIPTION
The default is read-only and saves both a human HTML report and technical JSON. To apply
supported fixes, supply Remediate together with ApprovedControlId. The script always runs
a no-change preview first and stops if the preview is incomplete.

This example assumes the listed item IDs were approved through your organization's change
process. EndpointForge records before and after values but does not automatically roll
back or restart Windows.
#>
[CmdletBinding()]
param(
    [string]$ReportDirectory = "$env:ProgramData\EndpointForge\Reports",
    [switch]$Remediate,
    [string[]]$ApprovedControlId,
    [switch]$ExitWithCode
)

$ErrorActionPreference = 'Stop'
Import-Module EndpointForge -MinimumVersion 0.4.0

Set-EFConfiguration -LogPath "$env:ProgramData\EndpointForge\endpointforge.jsonl" -LogLevel Information

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$check = Get-EFEndpointSummary -NoProgress
$check | Export-EFEndpointReport -Path (Join-Path $ReportDirectory "computer-check-$timestamp.json") -Force | Out-Null
$check | Export-EFEndpointReport -Path (Join-Path $ReportDirectory "computer-check-$timestamp.html") -Force | Out-Null

$changeReceipt = $null
if ($Remediate) {
    if ($null -eq $ApprovedControlId -or $ApprovedControlId.Count -eq 0) {
        throw 'Remediate requires at least one explicitly approved checklist item ID in ApprovedControlId.'
    }

    $preview = Invoke-EFEndpointRemediation -ControlId $ApprovedControlId -WhatIf -Confirm:$false -NoProgress
    $preview | Export-EFEndpointReport -Path (Join-Path $ReportDirectory "change-preview-$timestamp.json") -Force | Out-Null
    if ($preview.FailureCount -gt 0) {
        throw 'The no-change preview was incomplete. No supported fix was applied.'
    }

    $changeReceipt = Invoke-EFEndpointRemediation -ControlId $ApprovedControlId -Confirm:$false -NoProgress
    $changeReceipt | Export-EFEndpointReport -Path (Join-Path $ReportDirectory "change-receipt-$timestamp.json") -Force | Out-Null
    $check = Get-EFEndpointSummary -NoProgress
}

$exitCode = if ($null -ne $changeReceipt) {
    [math]::Max($check.ExitCode, $changeReceipt.ExitCode)
}
else {
    $check.ExitCode
}

[pscustomobject]@{
    ComputerName       = $check.ComputerName
    OverallResult      = $check.OverallStatus
    ChecklistResult    = $check.ComplianceStatus
    ChangesCompleted   = if ($null -ne $changeReceipt) { $changeReceipt.ChangedCount } else { 0 }
    RebootRequired     = if ($null -ne $changeReceipt) { $changeReceipt.RebootRequired } else { $false }
    ExitCode           = $exitCode
}

if ($ExitWithCode) {
    exit $exitCode
}
