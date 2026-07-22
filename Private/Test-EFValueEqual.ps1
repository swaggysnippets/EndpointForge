function Test-EFValueEqual {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Actual,

        [AllowNull()]
        [object]$Desired
    )

    if ($null -eq $Actual -or $null -eq $Desired) {
        return $null -eq $Actual -and $null -eq $Desired
    }

    if ($Desired -is [bool]) {
        try {
            return [Convert]::ToBoolean($Actual) -eq $Desired
        }
        catch {
            return $false
        }
    }

    if ($Desired -is [byte] -or $Desired -is [int16] -or $Desired -is [int32] -or
        $Desired -is [int64] -or $Desired -is [decimal] -or $Desired -is [double]) {
        try {
            return [decimal]$Actual -eq [decimal]$Desired
        }
        catch {
            return $false
        }
    }

    if ($Desired -is [array]) {
        if ($Actual -isnot [array]) {
            return $false
        }
        return @(Compare-Object -ReferenceObject $Desired -DifferenceObject $Actual -SyncWindow 0).Count -eq 0
    }

    return [string]::Equals(
        [Convert]::ToString($Actual, [Globalization.CultureInfo]::InvariantCulture),
        [Convert]::ToString($Desired, [Globalization.CultureInfo]::InvariantCulture),
        [StringComparison]::OrdinalIgnoreCase
    )
}
