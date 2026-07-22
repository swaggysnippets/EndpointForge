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
    if ($controls.Count -gt 256) {
        throw [System.IO.InvalidDataException]::new("Baseline '$name' cannot contain more than 256 checklist items.")
    }

    $supportedTypes = @(
        'Registry', 'Service', 'FirewallProfile', 'Defender', 'WindowsOptionalFeature',
        'FileExists', 'FileContainsText', 'WindowsEvent', 'TcpPort',
        'BitLocker', 'SecureBoot', 'Tpm', 'PendingRestart', 'DiskSpace',
        'WindowsUpdateAvailable', 'InstalledApplication', 'ScheduledTaskHealth',
        'DefenderSignatureHealth', 'FileFreshness', 'CertificateExpiry',
        'DnsResolution', 'HttpEndpointHealth', 'ProcessRunning', 'LocalGroupMembership'
    )
    $reportOnlyTypes = @(
        'FileExists', 'FileContainsText', 'WindowsEvent', 'TcpPort', 'BitLocker', 'SecureBoot', 'Tpm',
        'PendingRestart', 'DiskSpace', 'WindowsUpdateAvailable', 'InstalledApplication',
        'ScheduledTaskHealth', 'DefenderSignatureHealth', 'FileFreshness', 'CertificateExpiry',
        'DnsResolution', 'HttpEndpointHealth', 'ProcessRunning', 'LocalGroupMembership'
    )
    $booleanDesiredTypes = @(
        'FirewallProfile', 'SecureBoot', 'FileExists', 'FileContainsText', 'WindowsEvent', 'TcpPort',
        'PendingRestart', 'DiskSpace', 'WindowsUpdateAvailable', 'InstalledApplication',
        'ScheduledTaskHealth', 'DefenderSignatureHealth', 'FileFreshness', 'CertificateExpiry',
        'DnsResolution', 'HttpEndpointHealth', 'ProcessRunning', 'LocalGroupMembership'
    )
    $ids = @{}
    $networkControlCount = 0
    $windowsUpdateControlCount = 0
    $installedApplicationControlCount = 0
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
            'LogName', 'ProviderName', 'HostName', 'Drive', 'ApplicationName', 'Publisher',
            'ProductCode', 'Scope', 'Architecture', 'ExactVersion', 'MinimumVersion',
            'TaskName', 'TaskPath', 'StoreLocation', 'StoreName', 'Thumbprint', 'Uri',
            'Method', 'ProcessName', 'GroupName', 'MemberName'
        )) {
            if (Test-EFPropertyPresent -InputObject $control -Name $textProperty) {
                & $assertSafeText (Get-EFPropertyValue -InputObject $control -Name $textProperty) "Control '$id' $textProperty"
            }
        }
        foreach ($strictStringProperty in @(
            'Path', 'Text', 'LogName', 'ProviderName', 'HostName', 'Drive', 'ApplicationName',
            'Publisher', 'ProductCode', 'Scope', 'Architecture', 'ExactVersion', 'MinimumVersion',
            'TaskName', 'TaskPath', 'StoreLocation', 'StoreName', 'Thumbprint', 'Uri',
            'Method', 'ProcessName', 'GroupName', 'MemberName'
        )) {
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
        if ($type -in $reportOnlyTypes -and
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
            'InstalledApplication'   { @('ApplicationName') }
            'ScheduledTaskHealth'    { @('TaskName', 'MaximumAgeMinutes') }
            'FileFreshness'          { @('Path', 'MaximumAgeMinutes') }
            'CertificateExpiry'      { @('Thumbprint') }
            'DnsResolution'          { @('HostName') }
            'HttpEndpointHealth'     { @('Uri') }
            'ProcessRunning'         { @('ProcessName') }
            'LocalGroupMembership'   { @('GroupName', 'MemberName') }
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
        if ($type -in $booleanDesiredTypes -and
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
        if ($type -in @('FileExists', 'FileContainsText', 'FileFreshness')) {
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
        if (Test-EFControlUsesNetwork -Control $control) {
            $networkControlCount++
            if ($networkControlCount -gt 32) {
                throw [System.IO.InvalidDataException]::new('A checklist cannot contain more than 32 network-active items.')
            }
        }
        if ($type -eq 'TcpPort') {
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
        if ($type -eq 'DiskSpace') {
            $drive = [string](Get-EFPropertyValue -InputObject $control -Name 'Drive' -Default '%SystemDrive%')
            if ($drive -ine '%SystemDrive%' -and $drive -notmatch '^[A-Za-z]:\\?$') {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' Drive must be %SystemDrive% or one exact drive letter such as C:."
                )
            }
            if (-not (Test-EFPropertyPresent -InputObject $control -Name 'MinimumFreePercent') -and
                -not (Test-EFPropertyPresent -InputObject $control -Name 'MinimumFreeGB')) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' must define MinimumFreePercent, MinimumFreeGB, or both."
                )
            }
            foreach ($propertyRule in @(
                @{ Name = 'MinimumFreePercent'; Minimum = 1; Maximum = 99 },
                @{ Name = 'MinimumFreeGB'; Minimum = 1; Maximum = 1048576 }
            )) {
                if (-not (Test-EFPropertyPresent -InputObject $control -Name $propertyRule.Name)) { continue }
                $propertyValue = Get-EFPropertyValue -InputObject $control -Name $propertyRule.Name
                if (-not (& $testInteger $propertyValue) -or [decimal]$propertyValue -lt $propertyRule.Minimum -or
                    [decimal]$propertyValue -gt $propertyRule.Maximum) {
                    throw [System.IO.InvalidDataException]::new(
                        "Control '$id' $($propertyRule.Name) must be a whole number from $($propertyRule.Minimum) through $($propertyRule.Maximum)."
                    )
                }
            }
        }
        if ($type -eq 'WindowsUpdateAvailable') {
            $windowsUpdateControlCount++
            if ($windowsUpdateControlCount -gt 1) {
                throw [System.IO.InvalidDataException]::new(
                    'A checklist can contain only one WindowsUpdateAvailable item so it performs no more than one fresh update scan.'
                )
            }
            foreach ($booleanProperty in @('IncludeOptional', 'IncludeDrivers')) {
                if ((Test-EFPropertyPresent -InputObject $control -Name $booleanProperty) -and
                    (Get-EFPropertyValue -InputObject $control -Name $booleanProperty) -isnot [bool]) {
                    throw [System.IO.InvalidDataException]::new("Control '$id' $booleanProperty must be a JSON Boolean.")
                }
            }
            foreach ($propertyRule in @(
                @{ Name = 'MaximumCount'; Default = 0; Minimum = 0; Maximum = 1000 },
                @{ Name = 'TimeoutSeconds'; Default = 120; Minimum = 10; Maximum = 600 }
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
        if ($type -eq 'InstalledApplication') {
            $installedApplicationControlCount++
            if ($installedApplicationControlCount -gt 32) {
                throw [System.IO.InvalidDataException]::new(
                    'A checklist cannot contain more than 32 InstalledApplication items.'
                )
            }
            $applicationName = [string](Get-EFPropertyValue -InputObject $control -Name 'ApplicationName')
            if ($applicationName.Length -gt 256 -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($applicationName)) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' ApplicationName must be one exact display name no longer than 256 characters and cannot contain wildcards."
                )
            }
            foreach ($optionalExactProperty in @('Publisher', 'ProductCode', 'ExactVersion', 'MinimumVersion')) {
                if (-not (Test-EFPropertyPresent -InputObject $control -Name $optionalExactProperty)) { continue }
                $optionalValue = [string](Get-EFPropertyValue -InputObject $control -Name $optionalExactProperty)
                if ([string]::IsNullOrWhiteSpace($optionalValue) -or $optionalValue.Length -gt 256 -or
                    [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($optionalValue)) {
                    throw [System.IO.InvalidDataException]::new(
                        "Control '$id' $optionalExactProperty must be a non-empty exact value no longer than 256 characters and cannot contain wildcards."
                    )
                }
            }
            $scope = [string](Get-EFPropertyValue -InputObject $control -Name 'Scope' -Default 'Machine')
            if ($scope -notin @('Machine', 'CurrentUser', 'All')) {
                throw [System.IO.InvalidDataException]::new("Control '$id' Scope must be Machine, CurrentUser, or All.")
            }
            $architecture = [string](Get-EFPropertyValue -InputObject $control -Name 'Architecture' -Default 'All')
            if ($architecture -notin @('All', 'x64', 'x86', 'User')) {
                throw [System.IO.InvalidDataException]::new("Control '$id' Architecture must be All, x64, x86, or User.")
            }
            if (($scope -eq 'Machine' -and $architecture -eq 'User') -or
                ($scope -eq 'CurrentUser' -and $architecture -in @('x64', 'x86'))) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' has an incompatible Scope and Architecture. Machine accepts All, x64, or x86; CurrentUser accepts All or User."
                )
            }
            if ((Test-EFPropertyPresent -InputObject $control -Name 'ExactVersion') -and
                (Test-EFPropertyPresent -InputObject $control -Name 'MinimumVersion')) {
                throw [System.IO.InvalidDataException]::new("Control '$id' cannot define both ExactVersion and MinimumVersion.")
            }
            if (Test-EFPropertyPresent -InputObject $control -Name 'MinimumVersion') {
                $parsedMinimumVersion = $null
                $minimumVersion = [string](Get-EFPropertyValue -InputObject $control -Name 'MinimumVersion')
                if ($minimumVersion -notmatch '^\d+(?:\.\d+){1,3}$' -or
                    -not [version]::TryParse($minimumVersion, [ref]$parsedMinimumVersion)) {
                    throw [System.IO.InvalidDataException]::new(
                        "Control '$id' MinimumVersion must be a Windows version such as 1.2, 1.2.3, or 1.2.3.4."
                    )
                }
            }
        }
        if ($type -eq 'ScheduledTaskHealth') {
            $taskName = [string](Get-EFPropertyValue -InputObject $control -Name 'TaskName')
            if ($taskName.Length -gt 256 -or $taskName -match '[/\\]' -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($taskName)) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' TaskName must be one exact task name without a path or wildcard."
                )
            }
            $taskPath = [string](Get-EFPropertyValue -InputObject $control -Name 'TaskPath' -Default '\')
            $taskPathSegments = if ($taskPath -eq '\') {
                @()
            }
            elseif ($taskPath.Length -ge 2) {
                @($taskPath.Substring(1, $taskPath.Length - 2) -split '\\')
            }
            else { @('') }
            $hasUnsafeTaskPathSegment = @($taskPathSegments | Where-Object { $_ -in @('.', '..') }).Count -gt 0
            if ($taskPath.Length -gt 1024 -or
                $taskPath -notmatch '^\\(?:[^\\/\x00-\x1F\x7F*?\[\]]+\\)*$' -or
                $hasUnsafeTaskPathSegment -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($taskPath)) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' TaskPath must be one exact path that begins and ends with a backslash, has no empty, dot, or dot-dot segment, and contains no wildcard; for example, \ or \Contoso\."
                )
            }
            $maximumAgeMinutes = Get-EFPropertyValue -InputObject $control -Name 'MaximumAgeMinutes'
            if (-not (& $testInteger $maximumAgeMinutes) -or [decimal]$maximumAgeMinutes -lt 1 -or
                [decimal]$maximumAgeMinutes -gt 525600) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' MaximumAgeMinutes must be a whole number from 1 through 525,600."
                )
            }
            $lastTaskResult = Get-EFPropertyValue -InputObject $control -Name 'ExpectedLastTaskResult' -Default 0
            if (-not (& $testInteger $lastTaskResult) -or [decimal]$lastTaskResult -lt 0 -or
                [decimal]$lastTaskResult -gt 4294967295) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' ExpectedLastTaskResult must be a whole number from 0 through 4,294,967,295."
                )
            }
            if ((Test-EFPropertyPresent -InputObject $control -Name 'RequireEnabled') -and
                (Get-EFPropertyValue -InputObject $control -Name 'RequireEnabled') -isnot [bool]) {
                throw [System.IO.InvalidDataException]::new("Control '$id' RequireEnabled must be a JSON Boolean.")
            }
        }
        if ($type -eq 'DefenderSignatureHealth') {
            $maximumAgeDays = Get-EFPropertyValue -InputObject $control -Name 'MaximumAgeDays' -Default 7
            if (-not (& $testInteger $maximumAgeDays) -or [decimal]$maximumAgeDays -lt 0 -or
                [decimal]$maximumAgeDays -gt 365) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' MaximumAgeDays must be a whole number from 0 through 365."
                )
            }
        }
        if ($type -eq 'FileFreshness') {
            $maximumAgeMinutes = Get-EFPropertyValue -InputObject $control -Name 'MaximumAgeMinutes'
            if (-not (& $testInteger $maximumAgeMinutes) -or [decimal]$maximumAgeMinutes -lt 1 -or
                [decimal]$maximumAgeMinutes -gt 525600) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' MaximumAgeMinutes must be a whole number from 1 through 525,600."
                )
            }
        }
        if ($type -eq 'CertificateExpiry') {
            $storeLocation = [string](Get-EFPropertyValue -InputObject $control -Name 'StoreLocation' -Default 'LocalMachine')
            if ($storeLocation -notin @('LocalMachine', 'CurrentUser')) {
                throw [System.IO.InvalidDataException]::new("Control '$id' StoreLocation must be LocalMachine or CurrentUser.")
            }
            $storeName = [string](Get-EFPropertyValue -InputObject $control -Name 'StoreName' -Default 'My')
            if ($storeName -notin @('My', 'Root', 'CA', 'AuthRoot', 'TrustedPeople', 'TrustedPublisher')) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' StoreName must be My, Root, CA, AuthRoot, TrustedPeople, or TrustedPublisher."
                )
            }
            $thumbprint = [string](Get-EFPropertyValue -InputObject $control -Name 'Thumbprint')
            if ($thumbprint -notmatch '^[A-Fa-f0-9]{40}$') {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' Thumbprint must contain exactly 40 hexadecimal characters without spaces."
                )
            }
            $minimumDaysRemaining = Get-EFPropertyValue -InputObject $control -Name 'MinimumDaysRemaining' -Default 30
            if (-not (& $testInteger $minimumDaysRemaining) -or [decimal]$minimumDaysRemaining -lt 0 -or
                [decimal]$minimumDaysRemaining -gt 3650) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' MinimumDaysRemaining must be a whole number from 0 through 3,650."
                )
            }
        }
        if ($type -eq 'DnsResolution') {
            $hostName = [string](Get-EFPropertyValue -InputObject $control -Name 'HostName')
            $absoluteDnsPattern = '^(?=.{1,254}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.?$'
            $parsedIpAddress = $null
            if ([Net.IPAddress]::TryParse($hostName.TrimEnd([char]'.'), [ref]$parsedIpAddress) -or
                $hostName -notmatch $absoluteDnsPattern) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' HostName must be one absolute multi-label DNS name such as app.contoso.example, without an IP address, URL, path, whitespace, or wildcard."
                )
            }
            $timeout = Get-EFPropertyValue -InputObject $control -Name 'TimeoutMilliseconds' -Default 3000
            if (-not (& $testInteger $timeout) -or [decimal]$timeout -lt 100 -or [decimal]$timeout -gt 30000) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' TimeoutMilliseconds must be a whole number from 100 through 30,000."
                )
            }
        }
        if ($type -eq 'HttpEndpointHealth') {
            $uriText = [string](Get-EFPropertyValue -InputObject $control -Name 'Uri')
            $parsedUri = $null
            if ($uriText.Length -gt 2048 -or
                -not [Uri]::TryCreate($uriText, [UriKind]::Absolute, [ref]$parsedUri) -or
                $parsedUri.AbsoluteUri.Length -gt 2048 -or
                $parsedUri.Scheme -notin @('http', 'https') -or
                [string]::IsNullOrWhiteSpace($parsedUri.Host) -or
                [Uri]::CheckHostName($parsedUri.Host) -eq [UriHostNameType]::Unknown -or
                ([Uri]::CheckHostName($parsedUri.Host) -eq [UriHostNameType]::Dns -and $parsedUri.Host -notmatch '\.') -or
                -not [string]::IsNullOrWhiteSpace($parsedUri.UserInfo) -or
                -not [string]::IsNullOrWhiteSpace($parsedUri.Fragment) -or
                -not [string]::IsNullOrWhiteSpace($parsedUri.Query) -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($uriText)) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' Uri must be one exact HTTP or HTTPS address without credentials, a query string, fragment, or wildcard."
                )
            }
            $method = [string](Get-EFPropertyValue -InputObject $control -Name 'Method' -Default 'Head')
            if ($method -notin @('Head', 'Get')) {
                throw [System.IO.InvalidDataException]::new("Control '$id' Method must be Head or Get.")
            }
            if ((Test-EFPropertyPresent -InputObject $control -Name 'AllowRedirects') -and
                (Get-EFPropertyValue -InputObject $control -Name 'AllowRedirects') -isnot [bool]) {
                throw [System.IO.InvalidDataException]::new("Control '$id' AllowRedirects must be a JSON Boolean.")
            }
            $expectedStatusCode = Get-EFPropertyValue -InputObject $control -Name 'ExpectedStatusCode' -Default 200
            if (-not (& $testInteger $expectedStatusCode) -or [decimal]$expectedStatusCode -lt 100 -or
                [decimal]$expectedStatusCode -gt 599) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' ExpectedStatusCode must be a whole number from 100 through 599."
                )
            }
            $timeout = Get-EFPropertyValue -InputObject $control -Name 'TimeoutMilliseconds' -Default 5000
            if (-not (& $testInteger $timeout) -or [decimal]$timeout -lt 100 -or [decimal]$timeout -gt 30000) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' TimeoutMilliseconds must be a whole number from 100 through 30,000."
                )
            }
        }
        if ($type -eq 'ProcessRunning') {
            $processName = [string](Get-EFPropertyValue -InputObject $control -Name 'ProcessName')
            $processBaseName = if ($processName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
                $processName.Substring(0, $processName.Length - 4)
            }
            else { $processName }
            if ($processName.Length -gt 128 -or $processName -match '[/\\:]' -or
                [string]::IsNullOrWhiteSpace($processBaseName) -or
                [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($processName)) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' ProcessName must be one exact program name without a path, drive, or wildcard."
                )
            }
        }
        if ($type -eq 'LocalGroupMembership') {
            foreach ($propertyName in @('GroupName', 'MemberName')) {
                $propertyValue = [string](Get-EFPropertyValue -InputObject $control -Name $propertyName)
                if ($propertyValue.Length -gt 256 -or
                    [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($propertyValue)) {
                    throw [System.IO.InvalidDataException]::new(
                        "Control '$id' $propertyName must be one exact name or SID no longer than 256 characters and cannot contain wildcards."
                    )
                }
            }
            $timeoutSeconds = Get-EFPropertyValue -InputObject $control -Name 'TimeoutSeconds' -Default 15
            if (-not (& $testInteger $timeoutSeconds) -or [decimal]$timeoutSeconds -lt 10 -or
                [decimal]$timeoutSeconds -gt 60) {
                throw [System.IO.InvalidDataException]::new(
                    "Control '$id' TimeoutSeconds must be a whole number from 10 through 60."
                )
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
