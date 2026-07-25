function ConvertTo-EFFlatRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [switch]$AllowUnsafeCsvFormulaValues
    )

    $record = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $columnName = [string]$property.Name
        if (-not $AllowUnsafeCsvFormulaValues -and $columnName -match '^[=+\-@\t\r\n]') {
            $columnName = "'$columnName"
        }
        while ($record.Contains($columnName)) {
            $columnName = "'$columnName"
        }

        $value = $property.Value
        if ($value -is [DateTime]) {
            $record[$columnName] = ([DateTime]$value).ToUniversalTime().ToString('o')
        }
        elseif ($value -is [DateTimeOffset]) {
            $record[$columnName] = ([DateTimeOffset]$value).ToUniversalTime().ToString('o')
        }
        elseif ($value -is [string] -or $value -is [char]) {
            $textValue = [string]$value
            if (-not $AllowUnsafeCsvFormulaValues -and $textValue -match '^[=+\-@\t\r\n]') {
                $textValue = "'$textValue"
            }
            $record[$columnName] = $textValue
        }
        elseif ($null -eq $value -or $value -is [ValueType]) {
            $record[$columnName] = $value
        }
        else {
            $record[$columnName] = ConvertTo-EFSerializableValue -InputObject $value | ConvertTo-Json -Depth 10 -Compress
        }
    }
    return [pscustomobject]$record
}
