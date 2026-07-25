function Test-EFIpRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$ApprovedRanges,

        [AllowNull()]
        [string]$InterfaceName,

        [ValidateRange(1, 30)]
        [int]$TimeoutSeconds = 10
    )

    if ($ApprovedRanges -is [string] -or $ApprovedRanges -isnot [Collections.IEnumerable]) {
        throw [System.ArgumentException]::new(
            'ApprovedRanges must be an array containing from 1 through 32 CIDR network ranges.'
        )
    }
    $rangeItems = @($ApprovedRanges)
    if ($rangeItems.Count -lt 1 -or $rangeItems.Count -gt 32) {
        throw [System.ArgumentException]::new(
            'ApprovedRanges must contain from 1 through 32 CIDR network ranges.'
        )
    }
    if (-not [string]::IsNullOrEmpty($InterfaceName) -and
        ($InterfaceName.Length -gt 256 -or $InterfaceName -ne $InterfaceName.Trim() -or
         $InterfaceName -match '[\u0000-\u001F\u007F]' -or
         [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($InterfaceName))) {
        throw [System.ArgumentException]::new(
            'InterfaceName must be one exact local network connection name from 1 through 256 characters, without leading or trailing whitespace, control characters, or wildcards.'
        )
    }

    $seenNetworks = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $networks = @(
        foreach ($approvedRange in $rangeItems) {
            if ($approvedRange -isnot [string]) {
                throw [System.ArgumentException]::new(
                    'Every ApprovedRanges item must be a string.'
                )
            }
            $network = ConvertTo-EFIpNetwork -Cidr $approvedRange
            if (-not $seenNetworks.Add([string]$network.CanonicalKey)) {
                throw [System.ArgumentException]::new(
                    'ApprovedRanges cannot contain the same network more than once.'
                )
            }
            $network
        }
    )
    $workerNetworks = @(
        foreach ($network in $networks) {
            [ordered]@{
                Family       = [string]$network.Family
                PrefixLength = [int]$network.PrefixLength
                NetworkBase64 = [Convert]::ToBase64String([byte[]]$network.NetworkBytes)
            }
        }
    )

    $worker = {
        param($InputData)

        if ($null -eq ('Net.NetworkInformation.NetworkInterface' -as [type])) {
            return [pscustomobject]@{
                ProviderAvailable = $false
                Matches           = $false
                IsEvaluationError = $true
                FailureReason     = 'ProviderUnavailable'
            }
        }

        try {
            $interfaces = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces())
            if ($interfaces.Count -gt 128) {
                return [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches           = $false
                    IsEvaluationError = $true
                    FailureReason     = 'SafetyLimitExceeded'
                }
            }

            $requestedAlias = [string]$InputData.InterfaceName
            $hasRequestedAlias = -not [string]::IsNullOrEmpty($requestedAlias)
            $selectedInterfaces = [Collections.Generic.List[object]]::new()
            foreach ($networkInterface in $interfaces) {
                if (-not $hasRequestedAlias -or
                    [string]::Equals(
                        [string]$networkInterface.Name,
                        $requestedAlias,
                        [StringComparison]::OrdinalIgnoreCase
                    )) {
                    $selectedInterfaces.Add($networkInterface)
                }
            }
            if ($hasRequestedAlias -and $selectedInterfaces.Count -eq 0) {
                return [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches           = $false
                    IsEvaluationError = $true
                    FailureReason     = 'InterfaceNotFound'
                }
            }
            if ($hasRequestedAlias -and $selectedInterfaces.Count -gt 1) {
                return [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches           = $false
                    IsEvaluationError = $true
                    FailureReason     = 'AmbiguousInterface'
                }
            }
            if ($hasRequestedAlias -and
                ($selectedInterfaces[0].NetworkInterfaceType -eq
                    [Net.NetworkInformation.NetworkInterfaceType]::Loopback -or
                 $selectedInterfaces[0].OperationalStatus -ne
                    [Net.NetworkInformation.OperationalStatus]::Up)) {
                return [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches           = $false
                    IsEvaluationError = $true
                    FailureReason     = 'InterfaceUnavailable'
                }
            }

            $addressCount = 0
            $rangeMatches = $false
            $hadInterfaceReadFailure = $false
            foreach ($networkInterface in $selectedInterfaces) {
                if ($networkInterface.NetworkInterfaceType -eq
                    [Net.NetworkInformation.NetworkInterfaceType]::Loopback -or
                    $networkInterface.OperationalStatus -ne
                    [Net.NetworkInformation.OperationalStatus]::Up) {
                    continue
                }

                try {
                    $unicastAddresses = @($networkInterface.GetIPProperties().UnicastAddresses)
                    foreach ($unicastAddress in $unicastAddresses) {
                        $addressCount++
                        if ($addressCount -gt 256) {
                            return [pscustomobject]@{
                                ProviderAvailable = $true
                                Matches           = $false
                                IsEvaluationError = $true
                                FailureReason     = 'SafetyLimitExceeded'
                            }
                        }
                        if ($unicastAddress.DuplicateAddressDetectionState -ne
                            [Net.NetworkInformation.DuplicateAddressDetectionState]::Preferred) {
                            continue
                        }

                        $address = $unicastAddress.Address
                        if ($null -eq $address -or [Net.IPAddress]::IsLoopback($address) -or
                            $address.Equals([Net.IPAddress]::Any) -or
                            $address.Equals([Net.IPAddress]::IPv6Any) -or
                            ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6 -and
                                ($address.IsIPv4MappedToIPv6 -or $address.IsIPv6Multicast))) {
                            continue
                        }
                        [byte[]]$addressBytes = $address.GetAddressBytes()
                        if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
                            $addressBytes[0] -ge 224 -and $addressBytes[0] -le 239) {
                            continue
                        }

                        foreach ($network in @($InputData.Networks)) {
                            $expectedLength = if ([string]$network.Family -eq 'IPv4') { 4 } else { 16 }
                            if ($addressBytes.Length -ne $expectedLength) {
                                continue
                            }
                            [byte[]]$networkBytes = [Convert]::FromBase64String(
                                [string]$network.NetworkBase64
                            )
                            $prefixLength = [int]$network.PrefixLength
                            $isMatch = $true
                            for ($index = 0; $index -lt $addressBytes.Length; $index++) {
                                $bitsBeforeByte = $index * 8
                                $bitsInByte = [math]::Min(
                                    8,
                                    [math]::Max(0, $prefixLength - $bitsBeforeByte)
                                )
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
                                    $isMatch = $false
                                    break
                                }
                            }
                            if ($isMatch) {
                                $rangeMatches = $true
                                break
                            }
                        }
                        if ($rangeMatches) { break }
                    }
                }
                catch {
                    $hadInterfaceReadFailure = $true
                    continue
                }
                if ($rangeMatches) { break }
            }

            if (-not $rangeMatches -and $hadInterfaceReadFailure) {
                return [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches           = $false
                    IsEvaluationError = $true
                    FailureReason     = 'ProviderError'
                }
            }

            return [pscustomobject]@{
                ProviderAvailable = $true
                Matches           = $rangeMatches
                IsEvaluationError = $false
                FailureReason     = 'None'
            }
        }
        catch {
            return [pscustomobject]@{
                ProviderAvailable = $true
                Matches           = $false
                IsEvaluationError = $true
                FailureReason     = 'ProviderError'
            }
        }
    }

    try {
        $probe = Invoke-EFIsolatedCheck -ScriptBlock $worker -InputData @{
            Networks       = $workerNetworks
            InterfaceName  = if ($null -eq $InterfaceName) { '' } else { $InterfaceName }
        } -TimeoutMilliseconds ($TimeoutSeconds * 1000) -StartupAllowanceMilliseconds 3000 `
            -Activity 'The local IP range check'
    }
    catch [TimeoutException] {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Matches           = $false
            IsEvaluationError = $true
            FailureReason     = 'TimedOut'
        }
    }
    catch {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Matches           = $false
            IsEvaluationError = $true
            FailureReason     = 'WorkerFailure'
        }
    }

    foreach ($propertyName in @('ProviderAvailable', 'Matches', 'IsEvaluationError', 'FailureReason')) {
        if (-not (Test-EFPropertyPresent -InputObject $probe -Name $propertyName)) {
            return [pscustomobject]@{
                ProviderAvailable = $true
                Matches           = $false
                IsEvaluationError = $true
                FailureReason     = 'UnexpectedResult'
            }
        }
    }
    $failureReasons = @(
        'None', 'ProviderUnavailable', 'ProviderError', 'SafetyLimitExceeded',
        'InterfaceNotFound', 'AmbiguousInterface', 'InterfaceUnavailable',
        'TimedOut', 'WorkerFailure', 'UnexpectedResult'
    )
    if ($probe.ProviderAvailable -isnot [bool] -or $probe.Matches -isnot [bool] -or
        $probe.IsEvaluationError -isnot [bool] -or
        [string]$probe.FailureReason -notin $failureReasons) {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Matches           = $false
            IsEvaluationError = $true
            FailureReason     = 'UnexpectedResult'
        }
    }

    $providerAvailable = [bool]$probe.ProviderAvailable
    $rangeMatches = [bool]$probe.Matches
    $isEvaluationError = [bool]$probe.IsEvaluationError
    $failureReason = [string]$probe.FailureReason
    $isConsistentResult = if ($failureReason -eq 'None') {
        $providerAvailable -and -not $isEvaluationError
    }
    elseif ($failureReason -eq 'ProviderUnavailable') {
        -not $providerAvailable -and -not $rangeMatches -and $isEvaluationError
    }
    else {
        $providerAvailable -and -not $rangeMatches -and $isEvaluationError
    }
    if (-not $isConsistentResult) {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Matches           = $false
            IsEvaluationError = $true
            FailureReason     = 'UnexpectedResult'
        }
    }

    [pscustomobject]@{
        ProviderAvailable = $providerAvailable
        Matches           = $rangeMatches
        IsEvaluationError = $isEvaluationError
        FailureReason     = $failureReason
    }
}
