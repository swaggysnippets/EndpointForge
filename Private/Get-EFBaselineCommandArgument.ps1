function Get-EFBaselineCommandArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Baseline
    )

    $sourcePath = [string](Get-EFPropertyValue -InputObject $Baseline -Name 'SourcePath')
    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
        return $null
    }

    $builtInDataPath = [IO.Path]::GetFullPath((Join-Path $script:ModuleRoot 'Data')).TrimEnd('\') + '\'
    $resolvedSourcePath = [IO.Path]::GetFullPath($sourcePath)
    $value = if ($resolvedSourcePath.StartsWith($builtInDataPath, [StringComparison]::OrdinalIgnoreCase)) {
        [string](Get-EFPropertyValue -InputObject $Baseline -Name 'Name')
    }
    else {
        $resolvedSourcePath
    }
    return "-Baseline '$($value.Replace("'", "''"))'"
}
