function Get-EFControlState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Control
    )

    $type = [string](Get-EFPropertyValue -InputObject $Control -Name 'Type')
    $desiredValue = Get-EFPropertyValue -InputObject $Control -Name 'DesiredValue'

    try {
        switch ($type) {
            'Registry' {
                $path = [string](Get-EFPropertyValue -InputObject $Control -Name 'Path')
                $valueName = [string](Get-EFPropertyValue -InputObject $Control -Name 'ValueName')

                if (-not (Test-Path -LiteralPath $path)) {
                    return New-EFControlResult -Control $Control -Status NonCompliant -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Registry path '$path' does not exist."
                }

                $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
                $property = $item.PSObject.Properties[$valueName]
                if ($null -eq $property) {
                    return New-EFControlResult -Control $Control -Status NonCompliant -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Registry value '$valueName' does not exist."
                }

                $actual = $property.Value
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Registry value '$path\$valueName' evaluated."
            }

            'Service' {
                $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
                $service = Get-Service -Name $name -ErrorAction SilentlyContinue
                if ($null -eq $service) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Service '$name' is not installed."
                }

                $startupType = Get-EFPropertyValue -InputObject $service -Name 'StartType'
                if ($null -eq $startupType) {
                    $escapedName = $name.Replace("'", "''")
                    $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$escapedName'" -ErrorAction Stop
                    $startupType = switch ([string]$cimService.StartMode) {
                        'Auto' { 'Automatic' }
                        default { [string]$cimService.StartMode }
                    }
                }

                $desiredStartupType = [string](Get-EFPropertyValue -InputObject $Control -Name 'StartupType')
                $desiredStatus = [string](Get-EFPropertyValue -InputObject $Control -Name 'Status')
                $startupMatches = [string]::IsNullOrWhiteSpace($desiredStartupType) -or
                    (Test-EFValueEqual -Actual ([string]$startupType) -Desired $desiredStartupType)
                $statusMatches = [string]::IsNullOrWhiteSpace($desiredStatus) -or
                    (Test-EFValueEqual -Actual ([string]$service.Status) -Desired $desiredStatus)

                $actual = [ordered]@{
                    StartupType = [string]$startupType
                    Status      = [string]$service.Status
                }
                $desired = [ordered]@{
                    StartupType = $desiredStartupType
                    Status      = $desiredStatus
                }
                $resultStatus = if ($startupMatches -and $statusMatches) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $resultStatus -ActualValue $actual `
                    -DesiredValue $desired -Message "Service '$name' evaluated."
            }

            'FirewallProfile' {
                if ($null -eq (Get-Command -Name Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows Firewall cmdlets are unavailable.'
                }

                $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
                $firewallProfile = Get-NetFirewallProfile -Name $name -ErrorAction Stop
                $actual = [bool]$firewallProfile.Enabled
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Firewall profile '$name' evaluated."
            }

            'Defender' {
                if ($null -eq (Get-Command -Name Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Microsoft Defender cmdlets are unavailable.'
                }

                $propertyName = [string](Get-EFPropertyValue -InputObject $Control -Name 'Property')
                $defender = Get-MpComputerStatus -ErrorAction Stop
                $property = $defender.PSObject.Properties[$propertyName]
                if ($null -eq $property) {
                    throw "Microsoft Defender does not expose property '$propertyName'."
                }
                $actual = $property.Value
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Microsoft Defender property '$propertyName' evaluated."
            }

            'WindowsOptionalFeature' {
                if ($null -eq (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows optional feature cmdlets are unavailable.'
                }

                $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
                $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction SilentlyContinue
                if ($null -eq $feature) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Windows optional feature '$name' is unavailable."
                }
                $actual = [string]$feature.State
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Windows optional feature '$name' evaluated."
            }

            'FileExists' {
                $path = Resolve-EFLocalFilePath -Path ([string](Get-EFPropertyValue -InputObject $Control -Name 'Path')) `
                    -CheckExistingAncestors
                try {
                    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                    $actual = -not [bool]$item.PSIsContainer
                    $message = if ($actual) {
                        "The requested file exists at '$path'."
                    }
                    else {
                        "A folder exists at '$path', but the checklist asks for a file."
                    }
                }
                catch [System.Management.Automation.ItemNotFoundException] {
                    $actual = $false
                    $message = "No file exists at '$path'."
                }

                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'FileContainsText' {
                $path = Resolve-EFLocalFilePath -Path ([string](Get-EFPropertyValue -InputObject $Control -Name 'Path')) `
                    -CheckExistingAncestors
                $text = [string](Get-EFPropertyValue -InputObject $Control -Name 'Text')
                $tailLines = [int](Get-EFPropertyValue -InputObject $Control -Name 'TailLines' -Default 2000)
                $caseSensitive = [bool](Get-EFPropertyValue -InputObject $Control -Name 'CaseSensitive' -Default $false)
                $encoding = [string](Get-EFPropertyValue -InputObject $Control -Name 'Encoding' -Default 'Utf8')
                $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if ([bool]$item.PSIsContainer) {
                    throw "The path '$path' is a folder. This checklist item requires a text file."
                }

                $beforeLength = [int64]$item.Length
                $beforeWriteTime = $item.LastWriteTimeUtc
                $tail = Read-EFBoundedTextTail -Path $path -TailLines $tailLines -Encoding $encoding
                $lines = @($tail.Lines)
                $afterItem = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if ([int64]$afterItem.Length -ne $beforeLength -or $afterItem.LastWriteTimeUtc -ne $beforeWriteTime) {
                    throw "The text file '$path' changed while EndpointForge was reading it. Run the check again for a trustworthy answer."
                }

                $comparison = if ($caseSensitive) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
                $found = $false
                foreach ($line in $lines) {
                    if (([string]$line).IndexOf($text, $comparison) -ge 0) {
                        $found = $true
                        break
                    }
                }

                $status = if (Test-EFValueEqual -Actual $found -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $finding = if ($found) { 'was found' } else { 'was not found' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $found `
                    -DesiredValue $desiredValue -Message (
                        "Checked up to the most recent $tailLines lines in '$path'; the requested text $finding. File contents are not included in the result."
                    )
            }

            'WindowsEvent' {
                if ($null -eq (Get-Command -Name Get-WinEvent -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows event log commands are unavailable.'
                }

                $logName = [string](Get-EFPropertyValue -InputObject $Control -Name 'LogName')
                $eventIds = @((Get-EFPropertyValue -InputObject $Control -Name 'EventIds') | ForEach-Object { [int]$_ })
                $providerName = [string](Get-EFPropertyValue -InputObject $Control -Name 'ProviderName')
                $lookbackMinutes = [int](Get-EFPropertyValue -InputObject $Control -Name 'LookbackMinutes' -Default 60)
                $minimumCount = [int](Get-EFPropertyValue -InputObject $Control -Name 'MinimumCount' -Default 1)

                $eventLog = Get-WinEvent -ListLog $logName -ErrorAction Stop
                if ($null -eq $eventLog) {
                    throw "Windows did not return the event log '$logName'. Check the exact LogName."
                }
                if ((Test-EFPropertyPresent -InputObject $eventLog -Name 'IsEnabled') -and
                    -not [bool](Get-EFPropertyValue -InputObject $eventLog -Name 'IsEnabled')) {
                    throw "The Windows event log '$logName' is disabled, so it cannot provide trustworthy recent-event evidence."
                }
                $filter = @{
                    LogName  = $logName
                    Id       = [int[]]$eventIds
                    StartTime = [DateTime]::Now.AddMinutes(-$lookbackMinutes)
                }
                if (-not [string]::IsNullOrWhiteSpace($providerName)) {
                    $filter.ProviderName = $providerName
                }

                try {
                    $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $minimumCount -ErrorAction Stop)
                }
                catch {
                    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*' -or
                        $_.Exception.Message -match '^No events were found') {
                        $events = @()
                    }
                    else {
                        throw
                    }
                }

                $actual = $events.Count -ge $minimumCount
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $providerDescription = if ([string]::IsNullOrWhiteSpace($providerName)) { '' } else { " from '$providerName'" }
                $countDescription = if ($events.Count -ge $minimumCount) {
                    "Found at least $($events.Count) matching event(s)"
                }
                else {
                    "Found $($events.Count) matching event(s)"
                }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "$countDescription$providerDescription in '$logName' during the last $lookbackMinutes minute(s); at least $minimumCount were requested. Event messages are not included in the result."
                    )
            }

            'TcpPort' {
                $hostName = [string](Get-EFPropertyValue -InputObject $Control -Name 'HostName')
                $port = [int](Get-EFPropertyValue -InputObject $Control -Name 'Port')
                $timeoutMilliseconds = [int](Get-EFPropertyValue -InputObject $Control -Name 'TimeoutMilliseconds' -Default 3000)
                $probe = Test-EFTcpPort -HostName $hostName -Port $port -TimeoutMilliseconds $timeoutMilliseconds
                if ($probe.FailureReason -eq 'NameResolutionFailed') {
                    throw "The host name '$hostName' could not be resolved. Check the spelling and DNS configuration."
                }
                if ([bool]$probe.IsEvaluationError) {
                    throw "Windows could not complete the TCP port check for '$hostName' on port $port ($($probe.FailureReason))."
                }

                $actual = [bool]$probe.Connected
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $outcome = if ($actual) { 'accepted a TCP connection' } else { "did not accept a TCP connection ($($probe.FailureReason))" }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "'$hostName' port $port $outcome within $timeoutMilliseconds millisecond(s). EndpointForge opened and closed one TCP connection without sending application data."
                    )
            }

            'BitLocker' {
                if ($null -eq (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'BitLocker cmdlets are unavailable.'
                }

                $mountPoint = [Environment]::ExpandEnvironmentVariables(
                    [string](Get-EFPropertyValue -InputObject $Control -Name 'MountPoint' -Default '%SystemDrive%')
                )
                $volume = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop
                $actual = [string]$volume.ProtectionStatus
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "BitLocker volume '$mountPoint' evaluated."
            }

            'SecureBoot' {
                if ($null -eq (Get-Command -Name Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Secure Boot cmdlets are unavailable.'
                }

                try {
                    $actual = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
                }
                catch {
                    $secureBootMessage = $_.Exception.Message
                    $secureBootStatus = if ($secureBootMessage -match 'not supported|not available|not implemented') { 'NotApplicable' } else { 'Error' }
                    return New-EFControlResult -Control $Control -Status $secureBootStatus -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Secure Boot cannot be queried on this device: $secureBootMessage"
                }
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message 'Secure Boot evaluated.'
            }

            'Tpm' {
                if ($null -eq (Get-Command -Name Get-Tpm -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'TPM cmdlets are unavailable.'
                }

                $tpm = Get-Tpm -ErrorAction Stop
                if (-not (Test-EFPropertyPresent -InputObject $tpm -Name 'TpmPresent') -or
                    -not (Test-EFPropertyPresent -InputObject $tpm -Name 'TpmReady')) {
                    throw 'TPM status was not returned. Run PowerShell as Administrator to evaluate this control.'
                }
                $actual = [ordered]@{
                    TpmPresent = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmPresent')
                    TpmReady   = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmReady')
                }
                $expectedPresent = [bool](Get-EFPropertyValue -InputObject $desiredValue -Name 'TpmPresent' -Default $true)
                $expectedReady = [bool](Get-EFPropertyValue -InputObject $desiredValue -Name 'TpmReady' -Default $true)
                $isMatch = $actual.TpmPresent -eq $expectedPresent -and $actual.TpmReady -eq $expectedReady
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message 'Trusted Platform Module state evaluated.'
            }

            default {
                throw "Unsupported baseline control type '$type'."
            }
        }
    }
    catch {
        return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
            -DesiredValue $desiredValue -Message $_.Exception.Message
    }
}
