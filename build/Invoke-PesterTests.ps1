[CmdletBinding()]
param(
    [string]$TestResultPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pester = Get-Module -ListAvailable Pester |
    Where-Object Version -ge ([version]'5.5.0') |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($null -eq $pester) {
    throw 'Pester 5.5.0 or later is required to run the test suite.'
}

Import-Module $pester.Path -Force
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $projectRoot 'tests'
$configuration.Run.Exit = $false
$configuration.Output.Verbosity = 'Detailed'
if (-not [string]::IsNullOrWhiteSpace($TestResultPath)) {
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TestResultPath)
}

$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) Pester test(s) failed."
}
