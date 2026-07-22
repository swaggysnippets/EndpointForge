[CmdletBinding()]
param(
    [string]$ModulePath,

    [switch]$RequireSignature,

    [switch]$CheckGalleryName
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'artifacts\EndpointForge'
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
$manifestPath = Join-Path $resolvedModulePath 'EndpointForge.psd1'
$errors = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Staged manifest '$manifestPath' was not found. Run build\Build-Module.ps1 first."
}

$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$manifestData = Import-PowerShellDataFile -Path $manifestPath
$psData = $manifestData.PrivateData.PSData

if ([string]::IsNullOrWhiteSpace([string]$manifestData.Author) -or
    [string]$manifestData.Author -in @('EndpointForge Contributors', 'Unknown', 'TODO')) {
    $errors.Add('Replace the placeholder manifest Author with the accountable publisher name.')
}
if ([string]::IsNullOrWhiteSpace([string]$manifestData.CompanyName) -or
    [string]$manifestData.CompanyName -in @('Community', 'Unknown', 'TODO')) {
    $errors.Add('Replace the placeholder manifest CompanyName with the publisher or organization name.')
}
if ([string]::IsNullOrWhiteSpace([string]$psData.ProjectUri) -or [string]$psData.ProjectUri -notmatch '^https://') {
    $errors.Add('PSData.ProjectUri must be the HTTPS URL of the public source and support repository.')
}
if ([string]::IsNullOrWhiteSpace([string]$manifestData.HelpInfoURI) -or [string]$manifestData.HelpInfoURI -notmatch '^https://') {
    $errors.Add('HelpInfoURI must be an HTTPS documentation URL.')
}
if ([string]::IsNullOrWhiteSpace([string]$psData.LicenseUri) -or [string]$psData.LicenseUri -notmatch '^https://') {
    $errors.Add('PSData.LicenseUri must be an HTTPS license URL.')
}
if ([string]::IsNullOrWhiteSpace([string]$manifestData.Description)) {
    $errors.Add('The manifest Description is required.')
}
if (@($psData.Tags).Count -eq 0) {
    $errors.Add('At least one Gallery discovery tag is required.')
}
if ([string]::IsNullOrWhiteSpace([string]$psData.ReleaseNotes)) {
    $errors.Add('PSData.ReleaseNotes is required for this release.')
}

foreach ($requiredFile in @('LICENSE', 'README.md', 'SECURITY.md', 'CHANGELOG.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedModulePath $requiredFile) -PathType Leaf)) {
        $errors.Add("The staged package is missing required file '$requiredFile'.")
    }
}

$readmePath = Join-Path $resolvedModulePath 'README.md'
if (Test-Path -LiteralPath $readmePath -PathType Leaf) {
    $linkPattern = '\[[^\]]+\]\((?!https?://|mailto:|#)([^)]+)\)'
    $lineNumber = 0
    $insideCodeFence = $false
    foreach ($line in Get-Content -LiteralPath $readmePath) {
        $lineNumber++
        if ($line.TrimStart().StartsWith('```')) {
            $insideCodeFence = -not $insideCodeFence
            continue
        }
        if ($insideCodeFence) { continue }
        foreach ($match in [regex]::Matches($line, $linkPattern)) {
            $relativeTarget = [uri]::UnescapeDataString(($match.Groups[1].Value -split '#')[0])
            if ([string]::IsNullOrWhiteSpace($relativeTarget)) { continue }
            $targetPath = [IO.Path]::GetFullPath((Join-Path $resolvedModulePath $relativeTarget))
            $modulePrefix = [IO.Path]::GetFullPath($resolvedModulePath).TrimEnd('\') + '\'
            if (-not $targetPath.StartsWith($modulePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                $errors.Add("README.md line $lineNumber links outside the package: '$relativeTarget'.")
            }
            elseif (-not (Test-Path -LiteralPath $targetPath)) {
                $errors.Add("README.md line $lineNumber has a missing package-relative target: '$relativeTarget'.")
            }
        }
    }
}

$stagedFiles = @(Get-ChildItem -LiteralPath $resolvedModulePath -Recurse -File)
$forbiddenFiles = @($stagedFiles | Where-Object {
    $_.Name -match '(?i)^(\.env|id_rsa|id_ed25519)$' -or
    $_.Extension -match '(?i)^\.(pfx|p12|key|pem|log|tmp|jsonl)$' -or
    $_.FullName -match '(?i)[\\/](\.git|\.build|TestResults)[\\/]'
})
foreach ($forbiddenFile in $forbiddenFiles) {
    $errors.Add("Sensitive or development-only file is staged: '$($forbiddenFile.FullName.Substring($resolvedModulePath.Length + 1))'.")
}

$localPathReferences = @($stagedFiles | Where-Object Extension -in '.ps1', '.psm1', '.psd1', '.md', '.txt' |
    Select-String -Pattern '(?i)[A-Z]:\\Users\\[^\\]+' -ErrorAction SilentlyContinue)
foreach ($reference in $localPathReferences) {
    $errors.Add("Local user path found in '$($reference.Path.Substring($resolvedModulePath.Length + 1))' line $($reference.LineNumber).")
}

$signableFiles = @($stagedFiles | Where-Object Extension -in '.ps1', '.psm1', '.psd1', '.ps1xml')
$signatureResults = @($signableFiles | ForEach-Object { Get-AuthenticodeSignature -LiteralPath $_.FullName })
$unsignedCount = @($signatureResults | Where-Object Status -eq 'NotSigned').Count
$invalidSignatureCount = @($signatureResults | Where-Object Status -notin @('Valid', 'NotSigned')).Count
if ($invalidSignatureCount -gt 0) {
    $errors.Add("$invalidSignatureCount staged file(s) have an invalid or untrusted Authenticode signature.")
}
if ($unsignedCount -gt 0) {
    $message = "$unsignedCount staged PowerShell file(s) are not Authenticode signed."
    if ($RequireSignature) { $errors.Add($message) } else { $warnings.Add($message) }
}
if ([version]$manifest.Version -lt [version]'1.0.0') {
    $warnings.Add("Version $($manifest.Version) is a pre-1.0 release and should be described as preview quality.")
}

if ($CheckGalleryName) {
    try {
        $publishedModule = Find-Module -Name $manifest.Name -Repository PSGallery -ErrorAction Stop
        if ($null -ne $publishedModule) {
            $warnings.Add("Gallery package '$($manifest.Name)' already exists at version $($publishedModule.Version); confirm publisher ownership before release.")
        }
    }
    catch {
        if ($_.Exception.Message -notmatch 'No match was found|Unable to find') {
            $warnings.Add("Gallery name availability could not be checked: $($_.Exception.Message)")
        }
    }
}

$result = [pscustomobject]@{
    PSTypeName       = 'EndpointForge.PublishReadiness'
    Name             = $manifest.Name
    Version          = $manifest.Version
    ModulePath       = $resolvedModulePath
    IsReady          = $errors.Count -eq 0
    ExportedCommands = @($manifest.ExportedFunctions.Keys).Count
    StagedFiles      = $stagedFiles.Count
    SignedFiles      = @($signatureResults | Where-Object Status -eq 'Valid').Count
    UnsignedFiles    = $unsignedCount
    ErrorCount       = $errors.Count
    WarningCount     = $warnings.Count
    Errors           = @($errors)
    Warnings         = @($warnings)
}

if (-not $result.IsReady) {
    $detail = ($result.Errors | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    throw "EndpointForge publish-readiness validation failed:`n$detail"
}

$result
