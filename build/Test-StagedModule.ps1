[CmdletBinding()]
param(
    [string]$ModulePath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'artifacts\EndpointForge'
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
$manifestPath = Join-Path $resolvedModulePath 'EndpointForge.psd1'
$hashInventoryPath = Join-Path (Split-Path -Parent $resolvedModulePath) 'EndpointForge.sha256.json'

$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $manifestPath -Force -ErrorAction Stop

$commands = @(Get-Command -Module EndpointForge -CommandType Function)
$manifestData = Import-PowerShellDataFile -Path $manifestPath
$expectedCommandCount = @($manifestData.FunctionsToExport).Count
$stagedFiles = @(Get-ChildItem -LiteralPath $resolvedModulePath -Recurse -File)
$hashInventory = Get-Content -LiteralPath $hashInventoryPath -Raw | ConvertFrom-Json
if ($hashInventory -isnot [array]) {
    $hashInventory = @($hashInventory)
}
if ($commands.Count -ne $expectedCommandCount) {
    throw "The staged module exported $($commands.Count) commands; expected $expectedCommandCount."
}
if ($stagedFiles.Count -ne $hashInventory.Count) {
    throw "The staged file count ($($stagedFiles.Count)) does not match the hash inventory ($($hashInventory.Count))."
}

foreach ($hashEntry in $hashInventory) {
    $filePath = Join-Path $resolvedModulePath ([string]$hashEntry.Path)
    $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$hashEntry.Hash) {
        throw "SHA-256 verification failed for '$($hashEntry.Path)'."
    }
}

[pscustomobject]@{
    Name             = $manifest.Name
    Version          = $manifest.Version
    ExportedCommands = $commands.Count
    BuiltInControls  = @((Get-EFBaseline).Controls).Count
    StagedFiles      = $stagedFiles.Count
    HashEntries      = $hashInventory.Count
    PackageBytes     = ($stagedFiles | Measure-Object Length -Sum).Sum
    HashesVerified   = $true
}
