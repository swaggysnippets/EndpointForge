function Test-EFIpAddressInNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Net.IPAddress]$Address,

        [Parameter(Mandatory)]
        [object]$Network
    )

    [byte[]]$addressBytes = $Address.GetAddressBytes()
    [byte[]]$networkBytes = @($Network.NetworkBytes)
    if ($addressBytes.Length -ne $networkBytes.Length) {
        return $false
    }

    $prefixLength = [int]$Network.PrefixLength
    for ($index = 0; $index -lt $addressBytes.Length; $index++) {
        $bitsBeforeByte = $index * 8
        $bitsInByte = [math]::Min(8, [math]::Max(0, $prefixLength - $bitsBeforeByte))
        if ($bitsInByte -eq 0) {
            break
        }
        $networkMask = if ($bitsInByte -eq 8) {
            [byte]255
        }
        else {
            [byte](256 - (1 -shl (8 - $bitsInByte)))
        }
        if (($addressBytes[$index] -band $networkMask) -ne
            ($networkBytes[$index] -band $networkMask)) {
            return $false
        }
    }

    return $true
}
