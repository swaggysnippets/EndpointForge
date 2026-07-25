[CmdletBinding()]
param(
    [string]$ModulePath,

    [string]$HashInventoryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'artifacts\EndpointForge'
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
$manifestPath = Join-Path $resolvedModulePath 'EndpointForge.psd1'
if ([string]::IsNullOrWhiteSpace($HashInventoryPath)) {
    $HashInventoryPath = Join-Path (Split-Path -Parent $resolvedModulePath) 'EndpointForge.sha256.json'
}
$resolvedHashInventoryPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HashInventoryPath)
$moduleRootPrefix = [IO.Path]::GetFullPath($resolvedModulePath).TrimEnd('\') + '\'

if (-not (Test-Path -LiteralPath $resolvedModulePath -PathType Container)) {
    throw "The staged module directory does not exist: '$resolvedModulePath'."
}
if (-not (Test-Path -LiteralPath $resolvedHashInventoryPath -PathType Leaf)) {
    throw "The staged hash inventory does not exist: '$resolvedHashInventoryPath'."
}
if (((Get-Item -LiteralPath $resolvedModulePath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The staged module directory cannot be a reparse point.'
}
if (((Get-Item -LiteralPath $resolvedHashInventoryPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The staged hash inventory cannot be a reparse point.'
}

try {
    $hashInventoryDocument = Get-Content -LiteralPath $resolvedHashInventoryPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "The staged hash inventory is not valid JSON: '$resolvedHashInventoryPath'."
}
if ($hashInventoryDocument -isnot [array] -or $hashInventoryDocument.Count -eq 0) {
    throw 'The staged hash inventory must be a non-empty JSON array.'
}

$hashInventory = @($hashInventoryDocument)
$stagedEntries = @(Get-ChildItem -LiteralPath $resolvedModulePath -Recurse -Force)
$stagedReparsePoints = @($stagedEntries | Where-Object {
    ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
})
if ($stagedReparsePoints.Count -gt 0) {
    throw "The staged module contains a reparse point: '$($stagedReparsePoints[0].FullName)'."
}
$stagedFiles = @($stagedEntries | Where-Object { -not $_.PSIsContainer })
if ($stagedFiles.Count -ne $hashInventory.Count) {
    throw "The staged file count ($($stagedFiles.Count)) does not match the hash inventory ($($hashInventory.Count))."
}

$seenInventoryPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$requiredInventoryProperties = @('Algorithm', 'Hash', 'Path')
foreach ($hashEntry in $hashInventory) {
    if ($null -eq $hashEntry -or $hashEntry -isnot [psobject]) {
        throw 'Every staged hash inventory entry must be a JSON object.'
    }
    $inventoryProperties = @($hashEntry.PSObject.Properties.Name | Sort-Object)
    if (($inventoryProperties -join "`n") -cne ($requiredInventoryProperties -join "`n")) {
        throw 'Every staged hash inventory entry must contain exactly Path, Algorithm, and Hash.'
    }
    if ($hashEntry.Path -isnot [string] -or
        $hashEntry.Algorithm -isnot [string] -or
        $hashEntry.Hash -isnot [string]) {
        throw 'Every staged hash inventory Path, Algorithm, and Hash value must be a string.'
    }

    $relativePath = [string]$hashEntry.Path
    $algorithm = [string]$hashEntry.Algorithm
    $expectedHash = [string]$hashEntry.Hash
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath)) {
        throw "The hash inventory contains an empty or absolute path: '$relativePath'."
    }
    if ($algorithm -cne 'SHA256' -or $expectedHash -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "The hash inventory entry for '$relativePath' is not a valid SHA-256 record."
    }

    try {
        $filePath = [IO.Path]::GetFullPath((Join-Path $resolvedModulePath $relativePath))
    }
    catch {
        throw "The hash inventory contains an invalid path: '$relativePath'."
    }
    if (-not $filePath.StartsWith($moduleRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The hash inventory path '$relativePath' escapes the staged module."
    }
    $canonicalRelativePath = $filePath.Substring($moduleRootPrefix.Length)
    if ($relativePath -cne $canonicalRelativePath) {
        throw "The hash inventory path '$relativePath' is not in canonical package form."
    }
    if (-not $seenInventoryPaths.Add($canonicalRelativePath)) {
        throw "The hash inventory contains the path '$relativePath' more than once."
    }
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "The hash inventory references a missing file: '$relativePath'."
    }
    $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    if ($actualHash -cne $expectedHash.ToUpperInvariant()) {
        throw "SHA-256 verification failed for '$relativePath'."
    }
}

foreach ($stagedFile in $stagedFiles) {
    $relativePath = $stagedFile.FullName.Substring($moduleRootPrefix.Length)
    if (-not $seenInventoryPaths.Contains($relativePath)) {
        throw "The staged file '$relativePath' is missing from the hash inventory."
    }
}

# Do not evaluate a staged manifest or import staged PowerShell until the inventory
# shape, exact file set, and every staged file hash have all been verified.
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $manifestPath -Force -ErrorAction Stop

$commands = @(Get-Command -Module EndpointForge -CommandType Function)
$manifestData = Import-PowerShellDataFile -Path $manifestPath
$expectedCommandCount = @($manifestData.FunctionsToExport).Count
if ($commands.Count -ne $expectedCommandCount) {
    throw "The staged module exported $($commands.Count) commands; expected $expectedCommandCount."
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
