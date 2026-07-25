[CmdletBinding()]
param(
    [string]$TestResultPath,

    [string]$RequiredVersion = $env:PESTER_VERSION,

    [switch]$CodeCoverage,

    [string]$CodeCoverageResultPath,

    [ValidateRange(0, 100)]
    [decimal]$MinimumCoveragePercent = 0,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$OutputVerbosity = 'Detailed'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$availablePester = @(Get-Module -ListAvailable Pester)
if (-not [string]::IsNullOrWhiteSpace($RequiredVersion)) {
    $requiredPesterVersion = [version]$RequiredVersion
    if ($requiredPesterVersion -lt [version]'5.5.0') {
        throw "Pester $requiredPesterVersion is not supported; version 5.5.0 or later is required."
    }
    $pester = $availablePester |
        Where-Object Version -eq $requiredPesterVersion |
        Select-Object -First 1
    if ($null -eq $pester) {
        throw "Required Pester version $requiredPesterVersion is not installed."
    }
}
else {
    $pester = $availablePester |
        Where-Object Version -ge ([version]'5.5.0') |
        Sort-Object Version -Descending |
        Select-Object -First 1
}
if ($null -eq $pester) {
    throw 'Pester 5.5.0 or later is required to run the test suite.'
}

Import-Module $pester.Path -Force
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $projectRoot 'tests'
$configuration.Run.Exit = $false
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = $OutputVerbosity
if (-not [string]::IsNullOrWhiteSpace($TestResultPath)) {
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TestResultPath)
}
if ($CodeCoverage) {
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = @(
        (Join-Path $projectRoot 'Public\*.ps1')
        (Join-Path $projectRoot 'Private\*.ps1')
    )
    $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
    if ([string]::IsNullOrWhiteSpace($CodeCoverageResultPath)) {
        $CodeCoverageResultPath = Join-Path $projectRoot 'TestResults\coverage.xml'
    }
    $coverageParent = Split-Path -Parent (
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CodeCoverageResultPath)
    )
    if (-not (Test-Path -LiteralPath $coverageParent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $coverageParent -Force
    }
    $configuration.CodeCoverage.OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $CodeCoverageResultPath
    )
}

$result = Invoke-Pester -Configuration $configuration
$failedContainerCount = if ($null -ne $result.PSObject.Properties['FailedContainersCount']) {
    [int]$result.FailedContainersCount
}
else {
    @($result.FailedContainers).Count
}
$failedBlockCount = if ($null -ne $result.PSObject.Properties['FailedBlocksCount']) {
    [int]$result.FailedBlocksCount
}
else {
    @($result.FailedBlocks).Count
}
$runFailed = [string]$result.Result -ne 'Passed'
if ($runFailed -or $result.FailedCount -gt 0 -or
    $failedContainerCount -gt 0 -or $failedBlockCount -gt 0) {
    throw (
        'Pester failed: {0} test(s), {1} block(s), and {2} container(s) failed; run result was {3}.' -f
        $result.FailedCount,
        $failedBlockCount,
        $failedContainerCount,
        $result.Result
    )
}
if ([int]$result.TotalCount -eq 0) {
    throw 'Pester discovered no tests.'
}
if ($CodeCoverage) {
    $coveragePercent = [decimal]$result.CodeCoverage.CoveragePercent
    Write-Output ("EndpointForge command coverage: {0:N2}%" -f $coveragePercent)
    if ($coveragePercent -lt $MinimumCoveragePercent) {
        throw "Command coverage $coveragePercent% is below the required $MinimumCoveragePercent%."
    }
}
