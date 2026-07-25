[CmdletBinding()]
param(
    [string]$ModulePath,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'artifacts\EndpointForge'
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $resolvedModulePath) 'EndpointForge.cdx.json'
}
$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$manifestPath = Join-Path $resolvedModulePath 'EndpointForge.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$moduleRootPrefix = [IO.Path]::GetFullPath($resolvedModulePath).TrimEnd('\') + '\'
$files = @(
    Get-ChildItem -LiteralPath $resolvedModulePath -File -Recurse |
        Sort-Object FullName |
        ForEach-Object {
            $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            [ordered]@{
                type = 'file'
                name = $_.FullName.Substring($moduleRootPrefix.Length).Replace('\', '/')
                hashes = @(
                    [ordered]@{
                        alg = 'SHA-256'
                        content = $hash.Hash.ToLowerInvariant()
                    }
                )
            }
        }
)
$sbom = [ordered]@{
    bomFormat = 'CycloneDX'
    specVersion = '1.5'
    serialNumber = "urn:uuid:$([guid]::NewGuid())"
    version = 1
    metadata = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString('o')
        tools = @(
            [ordered]@{
                vendor = 'EndpointForge'
                name = 'New-ReleaseSbom.ps1'
                version = $manifest.Version.ToString()
            }
        )
        component = [ordered]@{
            type = 'application'
            name = 'EndpointForge'
            version = $manifest.Version.ToString()
            licenses = @(
                [ordered]@{
                    license = [ordered]@{
                        id = 'MIT'
                    }
                }
            )
            externalReferences = @(
                [ordered]@{
                    type = 'vcs'
                    url = 'https://github.com/swaggysnippets/EndpointForge'
                }
                [ordered]@{
                    type = 'distribution'
                    url = "https://www.powershellgallery.com/packages/EndpointForge/$($manifest.Version)"
                }
            )
        }
    }
    components = $files
}

$outputParent = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outputParent -Force
}
[IO.File]::WriteAllText(
    $resolvedOutputPath,
    ($sbom | ConvertTo-Json -Depth 10),
    [Text.UTF8Encoding]::new($false)
)

[pscustomobject]@{
    PSTypeName   = 'EndpointForge.ReleaseSbom'
    Format       = 'CycloneDX'
    SpecVersion  = '1.5'
    ModuleVersion = $manifest.Version
    ComponentCount = $files.Count
    Path         = $resolvedOutputPath
}
