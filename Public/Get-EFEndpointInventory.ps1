function Get-EFEndpointInventory {
    <#
    .SYNOPSIS
    Collects normalized hardware, operating system, network, and security inventory.

    .DESCRIPTION
    Collects read-only local Windows inventory without querying Win32_Product. Features
    that are not installed or supported are represented as null and recorded in Errors,
    allowing collection to continue on heterogeneous fleets.

    .PARAMETER IncludeSoftware
    Includes registry-based installed software inventory in the returned object.

    .PARAMETER IncludeUser
    Includes the currently reported interactive user. It is excluded by default to
    minimize collection of user-identifying data.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    Get-EFEndpointInventory

    .EXAMPLE
    Get-EFEndpointInventory -IncludeSoftware | Export-EFEndpointReport -Path .\inventory.json

    .OUTPUTS
    EndpointForge.EndpointInventory

    .LINK
    Get-EFEndpointSummary
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeSoftware,
        [switch]$IncludeUser,
        [switch]$NoProgress
    )

    $null = Test-EFWindows -Throw
    $correlationId = [guid]::NewGuid().ToString()
    $errors = [Collections.Generic.List[string]]::new()
    Write-EFLog -Message 'Endpoint inventory collection started.' -CorrelationId $correlationId
    if (-not $NoProgress) {
        Write-Progress -Id 1101 -Activity 'EndpointForge inventory' -Status 'Collecting operating system and hardware data' -PercentComplete 5
    }

    $os = $null
    $computerSystem = $null
    $bios = $null
    $processor = $null
    $systemDisk = $null

    try { $os = Invoke-EFRetry -Operation 'Operating system inventory' -ScriptBlock { Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } }
    catch { $errors.Add("OperatingSystem: $($_.Exception.Message)") }
    try { $computerSystem = Invoke-EFRetry -Operation 'Computer system inventory' -ScriptBlock { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } }
    catch { $errors.Add("ComputerSystem: $($_.Exception.Message)") }
    try { $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop }
    catch { $errors.Add("BIOS: $($_.Exception.Message)") }
    try { $processor = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)[0] }
    catch { $errors.Add("Processor: $($_.Exception.Message)") }
    try {
        $escapedDrive = ([string]$env:SystemDrive).Replace("'", "''")
        $systemDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$escapedDrive'" -ErrorAction Stop
    }
    catch { $errors.Add("SystemDisk: $($_.Exception.Message)") }

    if (-not $NoProgress) {
        Write-Progress -Id 1101 -Activity 'EndpointForge inventory' -Status 'Collecting network configuration' -PercentComplete 35
    }

    $fqdn = $env:COMPUTERNAME
    try {
        $ipProperties = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        if (-not [string]::IsNullOrWhiteSpace($ipProperties.DomainName)) {
            $fqdn = "$env:COMPUTERNAME.$($ipProperties.DomainName)"
        }
    }
    catch { $errors.Add("FQDN: $($_.Exception.Message)") }

    $network = @()
    if ($null -ne (Get-Command -Name Get-NetIPConfiguration -ErrorAction SilentlyContinue)) {
        try {
            $network = @(
                Get-NetIPConfiguration -ErrorAction Stop |
                    Where-Object { $_.NetAdapter.Status -eq 'Up' } |
                    ForEach-Object {
                        [pscustomobject]@{
                            InterfaceAlias = $_.InterfaceAlias
                            MacAddress     = $_.NetAdapter.MacAddress
                            IPv4Address    = @($_.IPv4Address | ForEach-Object IPAddress)
                            IPv6Address    = @($_.IPv6Address | ForEach-Object IPAddress)
                            DefaultGateway = @($_.IPv4DefaultGateway | ForEach-Object NextHop)
                            DnsServer      = @($_.DNSServer.ServerAddresses)
                        }
                    }
            )
        }
        catch { $errors.Add("Network: $($_.Exception.Message)") }
    }

    if (-not $NoProgress) {
        Write-Progress -Id 1101 -Activity 'EndpointForge inventory' -Status 'Collecting hardware-backed security state' -PercentComplete 50
    }

    $secureBoot = $null
    if ($null -ne (Get-Command -Name Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
        try { $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) }
        catch { $errors.Add("SecureBoot: $($_.Exception.Message)") }
    }

    $tpmInfo = $null
    if ($null -ne (Get-Command -Name Get-Tpm -ErrorAction SilentlyContinue)) {
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            if (-not (Test-EFPropertyPresent -InputObject $tpm -Name 'TpmPresent')) {
                throw 'TPM status was not returned. Run PowerShell as Administrator for TPM inventory.'
            }
            $tpmInfo = [pscustomobject]@{
                Present          = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmPresent')
                Ready            = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmReady')
                Enabled          = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmEnabled')
                Activated        = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmActivated')
                ManagedAuthLevel = [string](Get-EFPropertyValue -InputObject $tpm -Name 'ManagedAuthLevel')
            }
        }
        catch { $errors.Add("TPM: $($_.Exception.Message)") }
    }

    $bitLockerInfo = $null
    if ($null -ne (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        try {
            $bitLocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
            $bitLockerInfo = [pscustomobject]@{
                MountPoint       = [string]$bitLocker.MountPoint
                VolumeStatus     = [string]$bitLocker.VolumeStatus
                ProtectionStatus = [string]$bitLocker.ProtectionStatus
                EncryptionMethod = [string]$bitLocker.EncryptionMethod
                EncryptionPercentage = [int]$bitLocker.EncryptionPercentage
            }
        }
        catch { $errors.Add("BitLocker: $($_.Exception.Message)") }
    }

    if (-not $NoProgress) {
        Write-Progress -Id 1101 -Activity 'EndpointForge inventory' -Status 'Collecting Defender and firewall state' -PercentComplete 70
    }

    $defenderInfo = $null
    if ($null -ne (Get-Command -Name Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        try {
            $defender = Get-MpComputerStatus -ErrorAction Stop
            $defenderInfo = [pscustomobject]@{
                AntivirusEnabled          = [bool]$defender.AntivirusEnabled
                AntispywareEnabled        = [bool]$defender.AntispywareEnabled
                RealTimeProtectionEnabled = [bool]$defender.RealTimeProtectionEnabled
                BehaviorMonitorEnabled    = [bool]$defender.BehaviorMonitorEnabled
                AntivirusSignatureVersion = [string]$defender.AntivirusSignatureVersion
                AntivirusSignatureAge     = [int]$defender.AntivirusSignatureAge
            }
        }
        catch { $errors.Add("Defender: $($_.Exception.Message)") }
    }

    $firewallInfo = @()
    if ($null -ne (Get-Command -Name Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
        try {
            $firewallInfo = @(
                Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        Name    = [string]$_.Name
                        Enabled = [bool]$_.Enabled
                    }
                }
            )
        }
        catch { $errors.Add("Firewall: $($_.Exception.Message)") }
    }

    $lastBoot = Get-EFPropertyValue -InputObject $os -Name 'LastBootUpTime'
    $uptime = if ($null -ne $lastBoot) { [DateTime]::Now - [DateTime]$lastBoot } else { $null }
    $diskSize = Get-EFPropertyValue -InputObject $systemDisk -Name 'Size'
    $diskFree = Get-EFPropertyValue -InputObject $systemDisk -Name 'FreeSpace'
    $diskPercent = if ($null -ne $diskSize -and [double]$diskSize -gt 0) {
        [math]::Round(([double]$diskFree / [double]$diskSize) * 100, 1)
    } else { $null }

    if (-not $NoProgress) {
        $softwareStatus = if ($IncludeSoftware) { 'Collecting installed software' } else { 'Finalizing endpoint inventory' }
        Write-Progress -Id 1101 -Activity 'EndpointForge inventory' -Status $softwareStatus -PercentComplete 90
    }

    $interactiveUser = if ($IncludeUser) { Get-EFPropertyValue -InputObject $computerSystem -Name 'UserName' } else { $null }
    $software = if ($IncludeSoftware) { @(Get-EFInstalledSoftware) } else { $null }

    $osCaption = Get-EFPropertyValue -InputObject $os -Name 'Caption'
    $osBuild = Get-EFPropertyValue -InputObject $os -Name 'BuildNumber'
    $deviceModel = Get-EFPropertyValue -InputObject $computerSystem -Name 'Model'
    $serialNumber = Get-EFPropertyValue -InputObject $bios -Name 'SerialNumber'
    $uptimeDays = if ($null -ne $uptime) { [math]::Round($uptime.TotalDays, 2) } else { $null }

    $inventory = [pscustomobject]@{
        PSTypeName       = 'EndpointForge.EndpointInventory'
        SchemaVersion    = '1.0'
        ComputerName     = $env:COMPUTERNAME
        Fqdn             = $fqdn
        CapturedAtUtc    = [DateTime]::UtcNow
        CorrelationId    = $correlationId
        OperatingSystemName = $osCaption
        OperatingSystemBuild = $osBuild
        DeviceModel      = $deviceModel
        SerialNumber     = $serialNumber
        UptimeDays       = $uptimeDays
        SystemDriveFreePercent = $diskPercent
        DataStatus       = if ($null -eq $os -and $null -eq $computerSystem) { 'Failed' } elseif ($errors.Count -gt 0) { 'Partial' } else { 'Complete' }
        CollectionErrorCount = $errors.Count
        InteractiveUser  = $interactiveUser
        ComputerSystem   = [pscustomobject]@{
            Manufacturer  = Get-EFPropertyValue -InputObject $computerSystem -Name 'Manufacturer'
            Model         = $deviceModel
            SerialNumber  = $serialNumber
            TotalMemoryGB = if ($null -ne (Get-EFPropertyValue -InputObject $computerSystem -Name 'TotalPhysicalMemory')) {
                [math]::Round([double](Get-EFPropertyValue -InputObject $computerSystem -Name 'TotalPhysicalMemory') / 1GB, 2)
            } else { $null }
            Processor     = Get-EFPropertyValue -InputObject $processor -Name 'Name'
            LogicalProcessors = Get-EFPropertyValue -InputObject $computerSystem -Name 'NumberOfLogicalProcessors'
            BiosVersion   = @((Get-EFPropertyValue -InputObject $bios -Name 'BIOSVersion')) -join '; '
        }
        OperatingSystem  = [pscustomobject]@{
            Caption        = $osCaption
            Version        = Get-EFPropertyValue -InputObject $os -Name 'Version'
            BuildNumber    = $osBuild
            Architecture   = Get-EFPropertyValue -InputObject $os -Name 'OSArchitecture'
            InstallDate    = Get-EFPropertyValue -InputObject $os -Name 'InstallDate'
            LastBootTime   = $lastBoot
            UptimeDays     = $uptimeDays
        }
        SystemDrive      = [pscustomobject]@{
            Drive              = $env:SystemDrive
            SizeGB             = if ($null -ne $diskSize) { [math]::Round([double]$diskSize / 1GB, 2) } else { $null }
            FreeGB             = if ($null -ne $diskFree) { [math]::Round([double]$diskFree / 1GB, 2) } else { $null }
            FreeSpacePercent   = $diskPercent
        }
        Network          = $network
        Security         = [pscustomobject]@{
            SecureBoot = $secureBoot
            Tpm        = $tpmInfo
            BitLocker  = $bitLockerInfo
            Defender   = $defenderInfo
            Firewall   = $firewallInfo
        }
        Software         = $software
        Errors           = @($errors)
    }

    Write-EFLog -Message 'Endpoint inventory collection completed.' `
        -Level $(if ($errors.Count -eq 0) { 'Information' } else { 'Warning' }) `
        -CorrelationId $correlationId -Data @{ errorCount = $errors.Count; includeSoftware = [bool]$IncludeSoftware }

    if (-not $NoProgress) {
        Write-Progress -Id 1101 -Activity 'EndpointForge inventory' -Completed
    }

    return $inventory
}
