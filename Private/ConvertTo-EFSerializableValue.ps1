function ConvertTo-EFSerializableValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [DateTime]) {
        return ([DateTime]$InputObject).ToUniversalTime().ToString('o')
    }
    if ($InputObject -is [DateTimeOffset]) {
        return ([DateTimeOffset]$InputObject).ToUniversalTime().ToString('o')
    }
    if ($InputObject -is [TimeSpan]) {
        return ([TimeSpan]$InputObject).ToString('c', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($InputObject -is [string] -or $InputObject -is [char] -or $InputObject -is [ValueType]) {
        return $InputObject
    }
    if ($InputObject -is [Collections.IDictionary]) {
        $dictionary = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $dictionary[[string]$key] = ConvertTo-EFSerializableValue -InputObject $InputObject[$key]
        }
        return [pscustomobject]$dictionary
    }
    if ($InputObject -is [Collections.IEnumerable]) {
        return @($InputObject | ForEach-Object { ConvertTo-EFSerializableValue -InputObject $_ })
    }

    $record = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')) {
            try {
                $record[$property.Name] = ConvertTo-EFSerializableValue -InputObject $property.Value
            }
            catch {
                $record[$property.Name] = $null
            }
        }
    }
    return [pscustomobject]$record
}
