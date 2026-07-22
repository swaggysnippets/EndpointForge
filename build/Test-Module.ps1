[CmdletBinding()]
param(
    [switch]$RequireScriptAnalyzer
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $projectRoot 'EndpointForge.psd1'
$failures = [Collections.Generic.List[string]]::new()
$excludedPathPattern = '[\\/](?:artifacts|\.build)[\\/]'

Write-Output 'Parsing PowerShell source files...'
$sourceFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
    Where-Object Extension -in @('.ps1', '.psm1', '.psd1') |
    Where-Object FullName -NotMatch $excludedPathPattern
foreach ($file in $sourceFiles) {
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        $failures.Add("Parse error in $($file.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)")
    }
}

Write-Output 'Validating the module manifest...'
try {
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    if ($manifest.Name -ne 'EndpointForge') {
        $failures.Add("Manifest name is '$($manifest.Name)', expected 'EndpointForge'.")
    }
}
catch {
    $failures.Add("Manifest validation failed: $($_.Exception.Message)")
}

$analyzer = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
if ($null -ne $analyzer) {
    Write-Output "Running PSScriptAnalyzer $($analyzer.Version)..."
    Import-Module $analyzer.Path -Force
    $analysis = @(
        foreach ($sourceFile in $sourceFiles) {
            Invoke-ScriptAnalyzer -Path $sourceFile.FullName -Severity Warning,Error
        }
    )
    foreach ($finding in $analysis) {
        $failures.Add("PSScriptAnalyzer $($finding.RuleName) in $($finding.ScriptName):$($finding.Line): $($finding.Message)")
    }
}
elseif ($RequireScriptAnalyzer) {
    $failures.Add('PSScriptAnalyzer is required but is not installed.')
}
else {
    Write-Warning 'PSScriptAnalyzer is not installed; static analysis was skipped.'
}

Write-Output 'Importing the module and checking its public contract...'
try {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $manifestPath -Force -ErrorAction Stop
    $manifestData = Import-PowerShellDataFile -Path $manifestPath
    $expectedCommands = @($manifestData.FunctionsToExport | Sort-Object)
    $actualCommands = @(Get-Command -Module EndpointForge -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
    $commandDifference = @(Compare-Object -ReferenceObject $expectedCommands -DifferenceObject $actualCommands)
    if ($commandDifference.Count -gt 0) {
        $failures.Add("Exported command contract differs: $($commandDifference | Out-String)")
    }

    foreach ($commandName in $expectedCommands) {
        $help = Get-Help $commandName
        if ([string]::IsNullOrWhiteSpace([string]$help.Synopsis) -or $help.Synopsis -match '^\s*$commandName\s*$') {
            $failures.Add("Command '$commandName' is missing a useful help synopsis.")
        }
    }

    $baseline = Get-EFBaseline
    if (@($baseline.Controls).Count -lt 1) {
        $failures.Add('The built-in baseline contains no controls.')
    }
    $duplicateIds = @($baseline.Controls | Group-Object Id | Where-Object Count -gt 1)
    if ($duplicateIds.Count -gt 0) {
        $failures.Add("The built-in baseline contains duplicate IDs: $($duplicateIds.Name -join ', ')")
    }

    $configuration = Set-EFConfiguration -LogLevel Debug -RetryCount 0 -RetryDelaySeconds 0 -PassThru
    if ($configuration.LogLevel -ne 'Debug' -or $configuration.RetryCount -ne 0) {
        $failures.Add('Configuration round-trip failed.')
    }
    Set-EFConfiguration -Reset

    $testDirectory = Join-Path ([IO.Path]::GetTempPath()) ("EndpointForge-Test-{0}" -f [guid]::NewGuid())
    try {
        $testReportPath = Join-Path $testDirectory 'report.json'
        [pscustomobject]@{ Name = 'SmokeTest'; Passed = $true } |
            Export-EFEndpointReport -Path $testReportPath -Force | Out-Null
        $exported = Get-Content -LiteralPath $testReportPath -Raw | ConvertFrom-Json
        if ($exported.Name -ne 'SmokeTest' -or -not $exported.Passed) {
            $failures.Add('JSON report export round-trip failed.')
        }
    }
    finally {
        if (Test-Path -LiteralPath $testDirectory) {
            $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
            $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            if ($resolvedTestDirectory.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetFileName($resolvedTestDirectory).StartsWith('EndpointForge-Test-', [StringComparison]::Ordinal)) {
                Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
            }
        }
    }
}
catch {
    $failures.Add("Module smoke test failed: $($_.Exception.Message)")
}
finally {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Warning $_ }
    throw "EndpointForge quality gate failed with $($failures.Count) issue(s)."
}

Write-Output 'EndpointForge quality gate passed.'
