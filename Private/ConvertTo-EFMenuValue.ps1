function ConvertTo-EFMenuValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return '<not available>'
    }
    if ($InputObject -is [string] -or $InputObject -is [ValueType]) {
        return [string]$InputObject
    }

    try {
        return ($InputObject | ConvertTo-Json -Depth 6 -Compress -ErrorAction Stop)
    }
    catch {
        return [string]$InputObject
    }
}
