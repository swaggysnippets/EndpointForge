function Assert-EFBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Baseline
    )

    $name = [string](Get-EFPropertyValue -InputObject $Baseline -Name 'Name')
    $version = [string](Get-EFPropertyValue -InputObject $Baseline -Name 'Version')
    $description = [string](Get-EFPropertyValue -InputObject $Baseline -Name 'Description')
    $controls = @(Get-EFPropertyValue -InputObject $Baseline -Name 'Controls')
    $assertSafeText = {
        param(
            [AllowNull()]
            [object]$Value,
            [Parameter(Mandatory)]
            [string]$Label
        )

        if ($null -ne $Value -and [string]$Value -match '[\x00-\x1F\x7F]') {
            throw [System.IO.InvalidDataException]::new("$Label must not contain control characters.")
        }
    }
    $testInteger = {
        param([AllowNull()][object]$Value)

        return $Value -is [byte] -or $Value -is [sbyte] -or
            $Value -is [int16] -or $Value -is [uint16] -or
            $Value -is [int32] -or $Value -is [uint32] -or
            $Value -is [int64] -or $Value -is [uint64]
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        throw [System.IO.InvalidDataException]::new('A baseline must define a non-empty Name.')
    }
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw [System.IO.InvalidDataException]::new("Baseline Name '$name' must contain only letters, numbers, dots, underscores, and hyphens.")
    }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw [System.IO.InvalidDataException]::new("Baseline '$name' must define a Version.")
    }
    if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        throw [System.IO.InvalidDataException]::new("Baseline '$name' Version '$version' is not a semantic version.")
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        throw [System.IO.InvalidDataException]::new("Baseline '$name' must define a non-empty Description.")
    }
    & $assertSafeText $name 'Baseline Name'
    & $assertSafeText $version "Baseline '$name' Version"
    & $assertSafeText $description "Baseline '$name' Description"
    if ($controls.Count -eq 0) {
        throw [System.IO.InvalidDataException]::new("Baseline '$name' must contain at least one control.")
    }

    $supportedTypes = @(
        'Registry', 'Service', 'FirewallProfile', 'Defender', 'WindowsOptionalFeature',
        'FileExists', 'FileContainsText', 'WindowsEvent', 'TcpPort',
        'BitLocker', 'SecureBoot', 'Tpm'
    )
    $ids = @{}
    $tcpControlCount = 0
    foreach ($control in $controls) {
        $id = [string](Get-EFPropertyValue -InputObject $control -Name 'Id')
        $type = [string](Get-EFPropertyValue -InputObject $control -Name 'Type')
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw [System.IO.InvalidDataException]::new("Baseline '$name' has a control without an Id.")
        }
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw [System.IO.InvalidDataException]::new("Control Id '$id' must contain only letters, numbers, dots, underscores, and hyphens.")
        }
        if ($ids.ContainsKey($id)) {
            throw [System.IO.InvalidDataException]::new("Baseline '$name' contains duplicate control Id '$id'.")
        }
        $ids[$id] = $true
        if ($type -notin $supportedTypes) {
            throw [System.IO.InvalidDataException]::new("Control '$id' uses unsupported Type '$type'.")
        }

        $title = [string](Get-EFPropertyValue -InputObject $control -Name 'Title')
        $severity = [string](Get-EFPropertyValue -InputObject $control -Name 'Severity')
        if ([string]::IsNullOrWhiteSpace($title)) {
            throw [System.IO.InvalidDataException]::new("Control '$id' must define a Title.")
        }
        if ($severity -notin @('Low', 'Medium', 'High', 'Critical')) {
            throw [System.IO.InvalidDataException]::new("Control '$id' has invalid Severity '$severity'.")
        }
        foreach ($textProperty in @(
            'Id', 'Title', 'Description', 'WhyItMatters', 'HowChecked', 'WhatWouldChange',
            'ManualAction', 'SafetyNotes', 'RecoveryGuidance', 'Type', 'Severity', 'Path',
            'ValueName', 'Name', 'Property', 'StartupType', 'Status', 'MountPoint', 'Text',
            'LogName', 'ProviderName', 'HostName'
        )) {
            if (Test-EFPropertyPresent -InputObject $control -Name $textProperty) {
                & $assertSafeText (Get-EFPropertyValue -InputObject $control -Name $textProperty) "Control '$id' $textProperty"
            }
        }
        foreach ($strictStringProperty in @('Path', 'Text', 'LogName', 'ProviderName', 'HostName')) {
            if ((Test-EFPropertyPresent -InputObject $control -Name $strictStringProperty) -and
                (Get-EFPropertyValue -InputObject $control -Name $strictStringProperty) -isnot [string]) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' $strictStringProperty must be a JSON string."
                )
            }
        }
        if (-not (Test-EFPropertyPresent -InputObject $control -Name 'DesiredValue')) {
            throw [System.IO.InvalidDataException]::new("Control '$id' must define DesiredValue.")
        }
        if (-not (Test-EFPropertyPresent -InputObject $control -Name 'Remediable')) {
            throw [System.IO.InvalidDataException]::new("Control '$id' must explicitly define Remediable.")
        }
        $remediableValue = Get-EFPropertyValue -InputObject $control -Name 'Remediable'
        if ($remediableValue -isnot [bool]) {
            $remediableType = if ($null -eq $remediableValue) { 'null' } else { $remediableValue.GetType().Name }
            throw [System.IO.InvalidDataException]::new("Control '$id' Remediable must be a JSON Boolean, not '$remediableType'.")
        }
        if ((Test-EFPropertyPresent -InputObject $control -Name 'RequiresReboot') -and
            (Get-EFPropertyValue -InputObject $control -Name 'RequiresReboot') -isnot [bool]) {
            throw [System.IO.InvalidDataException]::new("Control '$id' RequiresReboot must be a JSON Boolean.")
        }
        if ($type -in @('FileExists', 'FileContainsText', 'WindowsEvent', 'TcpPort') -and
            [bool](Get-EFPropertyValue -InputObject $control -Name 'RequiresReboot' -Default $false)) {
            throw [System.IO.InvalidDataException]::new("Control '$id' of type '$type' is report-only and cannot require a restart.")
        }
        if ([bool]$remediableValue -and $type -notin @('Registry', 'Service', 'FirewallProfile', 'Defender', 'WindowsOptionalFeature')) {
            throw [System.IO.InvalidDataException]::new("Control '$id' of type '$type' is audit-only and cannot set Remediable to true.")
        }

        $requiredByType = switch ($type) {
            'Registry'               { @('Path', 'ValueName') }
            'Service'                { @('Name') }
            'FirewallProfile'        { @('Name') }
            'Defender'               { @('Property') }
            'WindowsOptionalFeature' { @('Name') }
            'FileExists'             { @('Path') }
            'FileContainsText'       { @('Path', 'Text') }
            'WindowsEvent'           { @('LogName') }
            'TcpPort'                { @('HostName') }
            default                  { @() }
        }
        foreach ($requiredProperty in $requiredByType) {
            if ([string]::IsNullOrWhiteSpace([string](Get-EFPropertyValue -InputObject $control -Name $requiredProperty))) {
                throw [System.IO.InvalidDataException]::new("Control '$id' of type '$type' must define $requiredProperty.")
            }
        }

        if ($type -eq 'Service') {
            $startupType = [string](Get-EFPropertyValue -InputObject $control -Name 'StartupType')
            $serviceStatus = [string](Get-EFPropertyValue -InputObject $control -Name 'Status')
            if ([string]::IsNullOrWhiteSpace($startupType) -and [string]::IsNullOrWhiteSpace($serviceStatus)) {
                throw [System.IO.InvalidDataException]::new("Service control '$id' must define StartupType, Status, or both.")
            }
            if (-not [string]::IsNullOrWhiteSpace($startupType) -and $startupType -notin @('Automatic', 'Manual', 'Disabled')) {
                throw [System.IO.InvalidDataException]::new("Service control '$id' has invalid StartupType '$startupType'.")
            }
            if (-not [string]::IsNullOrWhiteSpace($serviceStatus) -and $serviceStatus -notin @('Running', 'Stopped')) {
                throw [System.IO.InvalidDataException]::new("Service control '$id' has invalid Status '$serviceStatus'.")
            }
        }

        $desiredValue = Get-EFPropertyValue -InputObject $control -Name 'DesiredValue'
        if ($type -in @('FirewallProfile', 'SecureBoot', 'FileExists', 'FileContainsText', 'WindowsEvent', 'TcpPort') -and
            $desiredValue -isnot [bool]) {
            throw [System.IO.InvalidDataException]::new("Control '$id' DesiredValue must be a JSON Boolean for type '$type'.")
        }
        if ($type -eq 'Defender') {
            $defenderProperty = [string](Get-EFPropertyValue -InputObject $control -Name 'Property')
            if ([bool]$remediableValue -and $defenderProperty -ne 'RealTimeProtectionEnabled') {
                throw [System.IO.InvalidDataException]::new("Defender control '$id' can only be remediated automatically for RealTimeProtectionEnabled.")
            }
            if ($desiredValue -isnot [bool]) {
                throw [System.IO.InvalidDataException]::new("Defender control '$id' DesiredValue must be a JSON Boolean.")
            }
        }
        if ($type -eq 'WindowsOptionalFeature' -and [string]$desiredValue -notin @('Enabled', 'Disabled')) {
            throw [System.IO.InvalidDataException]::new("Optional feature control '$id' DesiredValue must be Enabled or Disabled.")
        }
        if ($type -eq 'Registry') {
            $registryPath = [string](Get-EFPropertyValue -InputObject $control -Name 'Path')
            if ($registryPath -notmatch '^(?i)(?:HKLM|HKCU):\\.+$') {
                throw [System.IO.InvalidDataException]::new(
                    "Registry control '$id' Path must use an HKLM:\ or HKCU:\ Registry provider path."
                )
            }
            $valueType = [string](Get-EFPropertyValue -InputObject $control -Name 'ValueType' -Default 'String')
            if ($valueType -notin @('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')) {
                throw [System.IO.InvalidDataException]::new("Registry control '$id' has unsupported ValueType '$valueType'.")
            }
            $isNumeric = $desiredValue -is [byte] -or $desiredValue -is [sbyte] -or
                $desiredValue -is [int16] -or $desiredValue -is [uint16] -or
                $desiredValue -is [int32] -or $desiredValue -is [uint32] -or
                $desiredValue -is [int64] -or $desiredValue -is [uint64] -or
                $desiredValue -is [single] -or $desiredValue -is [double] -or $desiredValue -is [decimal]
            if ($valueType -in @('DWord', 'QWord') -and -not $isNumeric) {
                throw [System.IO.InvalidDataException]::new("Registry control '$id' DesiredValue must be numeric for ValueType '$valueType'.")
            }
        }
        if ($type -in @('FileExists', 'FileContainsText')) {
            $filePath = [string](Get-EFPropertyValue -InputObject $control -Name 'Path')
            try {
                $null = Resolve-EFLocalFilePath -Path $filePath
            }
            catch {
                throw [System.IO.InvalidDataException]::new("Control '$id' has an unsafe file Path. $($_.Exception.Message)", $_.Exception)
            }
        }
        if ($type -eq 'FileContainsText') {
            $text = [string](Get-EFPropertyValue -InputObject $control -Name 'Text')
            if ([string]::IsNullOrWhiteSpace($text)) {
                throw [System.IO.InvalidDataException]::new("Control '$id' must define non-empty literal Text to find in the file.")
            }
            if ($text.Length -gt 1024) {
                throw [System.IO.InvalidDataException]::new("Control '$id' Text cannot be longer than 1,024 characters.")
            }
            if (Test-EFPropertyPresent -InputObject $control -Name 'TailLines') {
                $tailLines = Get-EFPropertyValue -InputObject $control -Name 'TailLines'
                if (-not (& $testInteger $tailLines) -or [decimal]$tailLines -lt 1 -or [decimal]$tailLines -gt 10000) {
                    throw [System.IO.InvalidDataException]::new("Control '$id' TailLines must be a whole number from 1 through 10,000.")
                }
            }
            if ((Test-EFPropertyPresent -InputObject $control -Name 'CaseSensitive') -and
                (Get-EFPropertyValue -InputObject $control -Name 'CaseSensitive') -isnot [bool]) {
                throw [System.IO.InvalidDataException]::new("Control '$id' CaseSensitive must be a JSON Boolean.")
            }
            $encoding = [string](Get-EFPropertyValue -InputObject $control -Name 'Encoding' -Default 'Utf8')
            if ($encoding -notin @('Utf8', 'Unicode', 'BigEndianUnicode', 'Ascii')) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' Encoding must be Utf8, Unicode, BigEndianUnicode, or Ascii."
                )
            }
        }
        if ($type -eq 'WindowsEvent') {
            if (-not (Test-EFPropertyPresent -InputObject $control -Name 'EventIds')) {
                throw [System.IO.InvalidDataException]::new("Control '$id' of type 'WindowsEvent' must define EventIds.")
            }
            $logName = [string](Get-EFPropertyValue -InputObject $control -Name 'LogName')
            $providerName = [string](Get-EFPropertyValue -InputObject $control -Name 'ProviderName')
            if ($logName.Length -gt 256 -or [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($logName)) {
                throw [System.IO.InvalidDataException]::new("Control '$id' LogName must name one exact Windows event log and cannot contain wildcards.")
            }
            if ($providerName.Length -gt 256 -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($providerName)) {
                throw [System.IO.InvalidDataException]::new("Control '$id' ProviderName must name one exact event source and cannot contain wildcards.")
            }
            if ((Test-EFPropertyPresent -InputObject $control -Name 'ProviderName') -and
                [string]::IsNullOrWhiteSpace($providerName)) {
                throw [System.IO.InvalidDataException]::new("Control '$id' ProviderName cannot be empty when it is included.")
            }

            $eventIds = @(Get-EFPropertyValue -InputObject $control -Name 'EventIds')
            if ($eventIds.Count -lt 1 -or $eventIds.Count -gt 64) {
                throw [System.IO.InvalidDataException]::new("Control '$id' EventIds must contain from 1 through 64 event IDs.")
            }
            $seenEventIds = @{}
            foreach ($eventId in $eventIds) {
                if (-not (& $testInteger $eventId) -or [decimal]$eventId -lt 0 -or [decimal]$eventId -gt 65535) {
                    throw [System.IO.InvalidDataException]::new("Control '$id' EventIds values must be whole numbers from 0 through 65,535.")
                }
                if ($seenEventIds.ContainsKey([string]$eventId)) {
                    throw [System.IO.InvalidDataException]::new("Control '$id' EventIds contains duplicate value '$eventId'.")
                }
                $seenEventIds[[string]$eventId] = $true
            }
            foreach ($propertyRule in @(
                @{ Name = 'LookbackMinutes'; Default = 60; Minimum = 1; Maximum = 10080 },
                @{ Name = 'MinimumCount'; Default = 1; Minimum = 1; Maximum = 1000 }
            )) {
                $propertyValue = Get-EFPropertyValue -InputObject $control -Name $propertyRule.Name -Default $propertyRule.Default
                if (-not (& $testInteger $propertyValue) -or [decimal]$propertyValue -lt $propertyRule.Minimum -or
                    [decimal]$propertyValue -gt $propertyRule.Maximum) {
                    throw [System.IO.InvalidDataException]::new(
                        "Control '$id' $($propertyRule.Name) must be a whole number from $($propertyRule.Minimum) through $($propertyRule.Maximum)."
                    )
                }
            }
        }
        if ($type -eq 'TcpPort') {
            $tcpControlCount++
            if ($tcpControlCount -gt 32) {
                throw [System.IO.InvalidDataException]::new('A checklist cannot contain more than 32 TcpPort items.')
            }
            $hostName = [string](Get-EFPropertyValue -InputObject $control -Name 'HostName')
            if ($hostName.Length -gt 255 -or $hostName -match '[\s/\\]' -or $hostName -match '://' -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($hostName) -or
                [Uri]::CheckHostName($hostName) -eq [UriHostNameType]::Unknown) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' HostName must be one exact DNS name or IP address, without a URL scheme, path, whitespace, or wildcard."
                )
            }
            if (-not (Test-EFPropertyPresent -InputObject $control -Name 'Port')) {
                throw [System.IO.InvalidDataException]::new("Control '$id' of type 'TcpPort' must define Port.")
            }
            $port = Get-EFPropertyValue -InputObject $control -Name 'Port'
            if (-not (& $testInteger $port) -or [decimal]$port -lt 1 -or [decimal]$port -gt 65535) {
                throw [System.IO.InvalidDataException]::new("Control '$id' Port must be a whole number from 1 through 65,535.")
            }
            $timeout = Get-EFPropertyValue -InputObject $control -Name 'TimeoutMilliseconds' -Default 3000
            if (-not (& $testInteger $timeout) -or [decimal]$timeout -lt 100 -or [decimal]$timeout -gt 10000) {
                throw [System.IO.InvalidDataException]::new("Control '$id' TimeoutMilliseconds must be a whole number from 100 through 10,000.")
            }
        }
        if ($type -eq 'BitLocker' -and [string]$desiredValue -ne 'On') {
            throw [System.IO.InvalidDataException]::new("BitLocker control '$id' DesiredValue must be On.")
        }
        if ($type -eq 'Tpm') {
            foreach ($tpmProperty in @('TpmPresent', 'TpmReady')) {
                if (-not (Test-EFPropertyPresent -InputObject $desiredValue -Name $tpmProperty) -or
                    (Get-EFPropertyValue -InputObject $desiredValue -Name $tpmProperty) -isnot [bool]) {
                    throw [System.IO.InvalidDataException]::new("TPM control '$id' DesiredValue.$tpmProperty must be a JSON Boolean.")
                }
            }
        }
    }
}
