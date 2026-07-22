[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ModulePath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Fa-f0-9]{40,64}$')]
    [string]$CertificateThumbprint,

    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$CertificateStoreLocation = 'CurrentUser',

    [Parameter(Mandatory)]
    [ValidatePattern('^https?://')]
    [string]$TimestampServer
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'artifacts\EndpointForge'
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
$resolvedProjectRoot = [IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
if (-not ([IO.Path]::GetFullPath($resolvedModulePath)).StartsWith($resolvedProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to sign a module outside the EndpointForge project: '$resolvedModulePath'."
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedModulePath 'EndpointForge.psd1') -PathType Leaf)) {
    throw "Staged EndpointForge manifest was not found beneath '$resolvedModulePath'."
}

$certificatePath = "Cert:\$CertificateStoreLocation\My\$CertificateThumbprint"
$certificate = Get-Item -LiteralPath $certificatePath -ErrorAction Stop
if (-not $certificate.HasPrivateKey) {
    throw "Certificate '$CertificateThumbprint' does not have an accessible private key."
}
if ($certificate.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow) {
    throw "Certificate '$CertificateThumbprint' has expired."
}
$codeSigningOid = '1.3.6.1.5.5.7.3.3'
$enhancedKeyUsageOids = @($certificate.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId.Value })
if ($codeSigningOid -notin $enhancedKeyUsageOids) {
    throw "Certificate '$CertificateThumbprint' is not valid for code signing."
}

$signableFiles = @(Get-ChildItem -LiteralPath $resolvedModulePath -Recurse -File |
    Where-Object Extension -in '.ps1', '.psm1', '.psd1', '.ps1xml' |
    Sort-Object FullName)
if ($signableFiles.Count -eq 0) {
    throw "No signable PowerShell files were found beneath '$resolvedModulePath'."
}

$signedCount = 0
foreach ($file in $signableFiles) {
    if ($PSCmdlet.ShouldProcess($file.FullName, "Authenticode sign with certificate $CertificateThumbprint")) {
        $signature = Set-AuthenticodeSignature -LiteralPath $file.FullName -Certificate $certificate `
            -TimestampServer $TimestampServer -HashAlgorithm SHA256 -ErrorAction Stop
        if ($signature.Status -ne 'Valid') {
            throw "Signing '$($file.FullName)' returned status '$($signature.Status)': $($signature.StatusMessage)"
        }
        $signedCount++
    }
}

if ($signedCount -gt 0) {
    $outputRoot = Split-Path -Parent $resolvedModulePath
    $hashes = Get-ChildItem -LiteralPath $resolvedModulePath -Recurse -File | Get-FileHash -Algorithm SHA256 |
        Select-Object @{Name='Path'; Expression={ $_.Path.Substring($resolvedModulePath.Length + 1) }}, Algorithm, Hash
    $hashPath = Join-Path $outputRoot 'EndpointForge.sha256.json'
    $hashJson = $hashes | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($hashPath, $hashJson, [Text.UTF8Encoding]::new($false))
}

[pscustomobject]@{
    ModulePath            = $resolvedModulePath
    CertificateThumbprint = $CertificateThumbprint
    TimestampServer       = $TimestampServer
    SignableFiles         = $signableFiles.Count
    SignedFiles           = $signedCount
    WhatIf                = [bool]$WhatIfPreference
    HashInventoryUpdated  = $signedCount -gt 0
}
