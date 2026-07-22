[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'artifacts'
}
$outputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$moduleOutput = Join-Path $outputRoot 'EndpointForge'

if (-not $SkipTests) {
    & (Join-Path $PSScriptRoot 'Test-Module.ps1')
}

if (Test-Path -LiteralPath $moduleOutput) {
    $resolvedProject = [IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
    $resolvedOutput = [IO.Path]::GetFullPath($moduleOutput)
    if (-not $resolvedOutput.StartsWith($resolvedProject, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean output outside the project: '$resolvedOutput'."
    }
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $moduleOutput -Force

$rootFiles = @(
    'EndpointForge.psd1', 'EndpointForge.psm1', 'EndpointForge.Format.ps1xml',
    'LICENSE', 'README.md', 'CHANGELOG.md', 'SECURITY.md', 'CONTRIBUTING.md'
)
foreach ($file in $rootFiles) {
    $sourcePath = Join-Path $projectRoot $file
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required package file is missing: '$sourcePath'."
    }
    Copy-Item -LiteralPath $sourcePath -Destination $moduleOutput -Force
}
foreach ($directory in @('Public', 'Private', 'Data', 'en-US', 'examples')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $moduleOutput -Recurse -Force
}

$stagedManifest = Join-Path $moduleOutput 'EndpointForge.psd1'
$module = Test-ModuleManifest -Path $stagedManifest -ErrorAction Stop
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $stagedManifest -Force -ErrorAction Stop
Remove-Module EndpointForge -Force

$hashes = Get-ChildItem -LiteralPath $moduleOutput -Recurse -File | Get-FileHash -Algorithm SHA256 |
    Select-Object @{Name='Path'; Expression={ $_.Path.Substring($moduleOutput.Length + 1) }}, Algorithm, Hash
$hashPath = Join-Path $outputRoot 'EndpointForge.sha256.json'
$hashJson = $hashes | ConvertTo-Json -Depth 3
[IO.File]::WriteAllText($hashPath, $hashJson, [Text.UTF8Encoding]::new($false))

Write-Output "Built EndpointForge $($module.Version) at '$moduleOutput'."
Write-Output "SHA-256 inventory: '$hashPath'."
Get-Item -LiteralPath $moduleOutput
