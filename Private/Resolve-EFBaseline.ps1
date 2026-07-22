function Resolve-EFBaseline {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended'
    )

    if ($null -eq $Baseline) {
        return Get-EFBaseline -Name 'EnterpriseRecommended'
    }

    if ($Baseline -is [string]) {
        if (Test-Path -LiteralPath $Baseline -PathType Leaf) {
            return Get-EFBaseline -Path $Baseline
        }
        if ([IO.Path]::IsPathRooted([string]$Baseline) -or [string]$Baseline -match '[\\/]' -or
            [string]$Baseline -match '\.json$') {
            return Get-EFBaseline -Path ([string]$Baseline)
        }
        return Get-EFBaseline -Name ([string]$Baseline)
    }

    Assert-EFBaseline -Baseline $Baseline
    return $Baseline
}
