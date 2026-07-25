function ConvertTo-EFBaselineSourceJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Baseline
    )

    $sourceBaseline = [ordered]@{}
    foreach ($propertyName in @('$schema', 'FormatVersion', 'Name', 'Version', 'Description', 'Controls')) {
        if (Test-EFPropertyPresent -InputObject $Baseline -Name $propertyName) {
            $sourceBaseline[$propertyName] = Get-EFPropertyValue -InputObject $Baseline -Name $propertyName
        }
    }

    # Baseline values are already restricted to JSON-compatible types by
    # Assert-EFBaseline. Passing the ordered source object directly also preserves
    # one-item JSON arrays, which PowerShell pipeline enumeration can otherwise unwrap.
    return ConvertTo-Json -InputObject $sourceBaseline -Depth 100 -Compress
}
