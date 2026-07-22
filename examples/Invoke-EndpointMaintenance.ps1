[CmdletBinding()]
param(
    [string]$ReportDirectory = "$env:ProgramData\EndpointForge\Reports",
    [switch]$Remediate,
    [switch]$ExitWithCode
)

$ErrorActionPreference = 'Stop'
Import-Module EndpointForge -MinimumVersion 0.2.0

Set-EFConfiguration -LogPath "$env:ProgramData\EndpointForge\endpointforge.jsonl" -LogLevel Information

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$health = Get-EFEndpointHealth
$compliance = Get-EFComplianceReport

$health | Export-EFEndpointReport -Path (Join-Path $ReportDirectory "health-$timestamp.json") -Force | Out-Null
$compliance | Export-EFEndpointReport -Path (Join-Path $ReportDirectory "compliance-$timestamp.json") -Force | Out-Null

if ($Remediate -and -not $compliance.IsCompliant) {
    $remediation = Invoke-EFEndpointRemediation -Confirm:$false
    $remediation | Export-EFEndpointReport -Path (Join-Path $ReportDirectory "remediation-$timestamp.json") -Force | Out-Null
    $exitCode = [math]::Max($health.ExitCode, $remediation.ExitCode)
}
else {
    $exitCode = [math]::Max($health.ExitCode, $compliance.ExitCode)
}

$result = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Health       = $health.Status
    Compliance   = $compliance.IsCompliant
    ExitCode     = $exitCode
}
$result

if ($ExitWithCode) {
    exit $exitCode
}
