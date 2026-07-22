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
        'BitLocker', 'SecureBoot', 'Tpm'
    )
    $ids = @{}
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
        foreach ($textProperty in @('Id', 'Title', 'Description', 'Type', 'Severity', 'Path', 'ValueName', 'Name', 'Property', 'StartupType', 'Status', 'MountPoint')) {
            if (Test-EFPropertyPresent -InputObject $control -Name $textProperty) {
                & $assertSafeText (Get-EFPropertyValue -InputObject $control -Name $textProperty) "Control '$id' $textProperty"
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
        if ([bool]$remediableValue -and $type -notin @('Registry', 'Service', 'FirewallProfile', 'Defender', 'WindowsOptionalFeature')) {
            throw [System.IO.InvalidDataException]::new("Control '$id' of type '$type' is audit-only and cannot set Remediable to true.")
        }

        $requiredByType = switch ($type) {
            'Registry'               { @('Path', 'ValueName') }
            'Service'                { @('Name') }
            'FirewallProfile'        { @('Name') }
            'Defender'               { @('Property') }
            'WindowsOptionalFeature' { @('Name') }
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
        if ($type -in @('FirewallProfile', 'SecureBoot') -and $desiredValue -isnot [bool]) {
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
