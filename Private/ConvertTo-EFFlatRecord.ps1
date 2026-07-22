function ConvertTo-EFFlatRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $record = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $value = $property.Value
        if ($value -is [DateTime]) {
            $record[$property.Name] = ([DateTime]$value).ToUniversalTime().ToString('o')
        }
        elseif ($value -is [DateTimeOffset]) {
            $record[$property.Name] = ([DateTimeOffset]$value).ToUniversalTime().ToString('o')
        }
        elseif ($null -eq $value -or $value -is [string] -or $value -is [ValueType]) {
            $record[$property.Name] = $value
        }
        else {
            $record[$property.Name] = ConvertTo-EFSerializableValue -InputObject $value | ConvertTo-Json -Depth 10 -Compress
        }
    }
    return [pscustomobject]$record
}
