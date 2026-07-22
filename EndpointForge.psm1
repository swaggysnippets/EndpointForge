Set-StrictMode -Version 2.0

$script:ModuleRoot = $PSScriptRoot
$script:EFConfiguration = [ordered]@{
    LogPath           = $null
    LogLevel          = 'Information'
    RetryCount        = 2
    RetryDelaySeconds = 2
}

$privateFiles = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File |
    Sort-Object -Property Name
$publicFiles = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File |
    Sort-Object -Property Name

foreach ($file in @($privateFiles) + @($publicFiles)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to load EndpointForge file '$($file.FullName)': $($_.Exception.Message)"
    }
}

Initialize-EFArgumentCompleter

$publicFunctions = $publicFiles.BaseName
Export-ModuleMember -Function $publicFunctions
