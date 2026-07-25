[CmdletBinding()]
param(
    [string]$ExpectedTag,

    [switch]$RequireCleanWorktree,

    [switch]$CheckGalleryVersion
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $projectRoot 'EndpointForge.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$manifestData = Import-PowerShellDataFile -Path $manifestPath
$version = $manifest.Version.ToString()
$errors = [Collections.Generic.List[string]]::new()

if (-not [string]::IsNullOrWhiteSpace($ExpectedTag) -and $ExpectedTag -cne "v$version") {
    $errors.Add("Expected tag '$ExpectedTag' does not match manifest version v$version.")
}
if ([string]::IsNullOrWhiteSpace([string]$manifestData.PrivateData.PSData.ReleaseNotes)) {
    $errors.Add('Manifest release notes are empty.')
}

$changelogPath = Join-Path $projectRoot 'CHANGELOG.md'
$changelog = Get-Content -LiteralPath $changelogPath -Raw
if ($changelog -notmatch "(?m)^## \[$([regex]::Escape($version))\](?:\s|$)") {
    $errors.Add("CHANGELOG.md does not contain a heading for $version.")
}

foreach ($requiredPath in @(
    'README.md',
    'SECURITY.md',
    'CONTRIBUTING.md',
    'docs\Compatibility.md',
    'docs\Public-Contract.md',
    'docs\Migration-to-1.0.md',
    'docs\Enterprise-Deployment.md',
    'docs\Release-Checklist.md',
    'Data\PublicContract.v1.json',
    'build\Test-ManagedCertificationEvidence.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $requiredPath) -PathType Leaf)) {
        $errors.Add("Required release document '$requiredPath' is missing.")
    }
}

$prohibitedPhraseMatches = @(
    Get-ChildItem -LiteralPath $projectRoot -File -Recurse |
        Where-Object {
            $_.FullName -notmatch '[\\/](?:\.git|artifacts|\.build|TestResults)[\\/]' -and
            $_.Extension -in @('.ps1', '.psm1', '.psd1', '.md', '.txt', '.json', '.yml')
        } |
        Select-String -Pattern '(?i)beginner[- ]friendly' -ErrorAction SilentlyContinue
)
if ($prohibitedPhraseMatches.Count -gt 0) {
    $errors.Add('Release content still contains retired audience-level wording.')
}

try {
    & (Join-Path $PSScriptRoot 'Test-PublicContract.ps1') | Out-Null
}
catch {
    $errors.Add("The public contract failed validation: $($_.Exception.Message)")
}

if ($RequireCleanWorktree) {
    $gitStatus = @(git -C $projectRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        $errors.Add('Git worktree status could not be read.')
    }
    elseif ($gitStatus.Count -gt 0) {
        $errors.Add('The release must be built from a clean Git worktree.')
    }
}

if ($CheckGalleryVersion) {
    try {
        $existing = Find-Module EndpointForge -RequiredVersion $version -Repository PSGallery -ErrorAction SilentlyContinue
        if ($null -ne $existing) {
            $errors.Add("EndpointForge $version already exists in the PowerShell Gallery; Gallery versions are immutable.")
        }
    }
    catch {
        $errors.Add("PowerShell Gallery version availability could not be checked: $($_.Exception.Message)")
    }
}

if ($errors.Count -gt 0) {
    $detail = ($errors | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    throw "EndpointForge release metadata validation failed:`n$detail"
}

[pscustomobject]@{
    PSTypeName   = 'EndpointForge.ReleaseMetadataValidation'
    Version      = $version
    ExpectedTag  = $ExpectedTag
    IsClean      = if ($RequireCleanWorktree) { $true } else { $null }
    IsValid      = $true
}
