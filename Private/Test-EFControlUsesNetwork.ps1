function Test-EFControlUsesNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Control
    )

    process {
        [string](Get-EFPropertyValue -InputObject $Control -Name 'Type') -in @(
            'TcpPort', 'DnsResolution', 'HttpEndpointHealth', 'WindowsUpdateAvailable',
            'LocalGroupMembership'
        )
    }
}
