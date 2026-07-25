function ConvertTo-EFIpNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Cidr
    )

    if ($Cidr.Length -gt 128 -or $Cidr -notmatch '^[0-9A-Fa-f:./]+$') {
        throw [System.ArgumentException]::new(
            'Each CIDR range must be 128 characters or fewer and contain only IP-address, slash, and prefix characters without whitespace or control characters.'
        )
    }

    $parts = @($Cidr.Split([char]'/'))
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or
        $parts[1] -notmatch '^(?:0|[1-9][0-9]{0,2})$') {
        throw [System.ArgumentException]::new(
            "Each CIDR range must contain one IP address and one prefix length separated by '/'."
        )
    }

    $addressText = [string]$parts[0]
    $prefixLength = [int]$parts[1]
    $parsedAddress = $null
    $family = $null
    if ($addressText.Contains(':')) {
        if ($addressText -notmatch '^[0-9A-Fa-f:]+$' -or $addressText.Contains('.') -or
            $addressText.Contains('%') -or
            -not [Net.IPAddress]::TryParse($addressText, [ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6 -or
            $parsedAddress.IsIPv4MappedToIPv6 -or $parsedAddress.ScopeId -ne 0 -or
            $prefixLength -lt 1 -or $prefixLength -gt 128) {
            throw [System.ArgumentException]::new(
                'Each IPv6 CIDR range must use one ordinary network address with a prefix from 1 through 128. Scope IDs and embedded IPv4 forms are not accepted.'
            )
        }
        $family = 'IPv6'
    }
    else {
        if ($addressText -notmatch '^(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}$') {
            throw [System.ArgumentException]::new(
                'Each IPv4 CIDR range must use four decimal numbers without leading zeros.'
            )
        }
        foreach ($octet in @($addressText.Split([char]'.'))) {
            if ([int]$octet -gt 255) {
                throw [System.ArgumentException]::new(
                    'Each IPv4 CIDR number must be from 0 through 255.'
                )
            }
        }
        if (-not [Net.IPAddress]::TryParse($addressText, [ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            $prefixLength -lt 1 -or $prefixLength -gt 32) {
            throw [System.ArgumentException]::new(
                'Each IPv4 CIDR range must use one network address with a prefix from 1 through 32.'
            )
        }
        $family = 'IPv4'
    }

    [byte[]]$addressBytes = $parsedAddress.GetAddressBytes()
    for ($index = 0; $index -lt $addressBytes.Length; $index++) {
        $bitsBeforeByte = $index * 8
        $bitsInByte = [math]::Min(8, [math]::Max(0, $prefixLength - $bitsBeforeByte))
        $networkMask = if ($bitsInByte -eq 0) {
            [byte]0
        }
        elseif ($bitsInByte -eq 8) {
            [byte]255
        }
        else {
            [byte](256 - (1 -shl (8 - $bitsInByte)))
        }
        $hostMask = [byte](255 - $networkMask)
        if (($addressBytes[$index] -band $hostMask) -ne 0) {
            throw [System.ArgumentException]::new(
                "Each CIDR range must begin with the network address. Clear the host bits after the '/$prefixLength' prefix."
            )
        }
    }

    [pscustomobject]@{
        Family        = $family
        PrefixLength  = $prefixLength
        NetworkBytes  = [byte[]]$addressBytes
        CanonicalKey  = '{0}|{1}|{2}' -f $family, $prefixLength,
            [Convert]::ToBase64String([byte[]]$addressBytes)
    }
}
