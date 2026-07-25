function Get-EFManagementAgentState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Definition,

        [ValidateRange(1, 30)]
        [int]$TimeoutSeconds = 10
    )

    $serviceKeyExists = $false
    $serviceRegistryReadable = $true
    $startupType = $null
    $registryBase = $null
    $serviceKey = $null
    try {
        $registryBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Default
        )
        $serviceKey = $registryBase.OpenSubKey([string]$Definition.ServiceRegistryPath, $false)
        if ($null -ne $serviceKey) {
            $serviceKeyExists = $true
            $startValue = $serviceKey.GetValue('Start', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($null -ne $startValue) {
                $startupType = switch ([int]$startValue) {
                    0 { 'Boot' }
                    1 { 'System' }
                    2 { 'Automatic' }
                    3 { 'Manual' }
                    4 { 'Disabled' }
                    default { 'Unknown' }
                }
            }
        }
    }
    catch {
        $serviceRegistryReadable = $false
    }
    finally {
        if ($null -ne $serviceKey) { $serviceKey.Dispose() }
        if ($null -ne $registryBase) { $registryBase.Dispose() }
    }

    $installed = $false
    $serviceStatus = $null
    $serviceQuerySucceeded = $false
    $serviceController = $null
    try {
        $serviceController = Get-EFManagementAgentServiceController -ServiceName ([string]$Definition.ServiceName)
        $serviceController.Refresh()
        $serviceStatus = $serviceController.Status.ToString()
        $serviceQuerySucceeded = $true
        $installed = $true
    }
    catch {
        $installed = $serviceKeyExists
    }
    finally {
        if ($null -ne $serviceController) { $serviceController.Dispose() }
    }

    $version = $null
    try {
        if ([IO.File]::Exists([string]$Definition.VersionFilePath)) {
            $rawVersion = [string]([Diagnostics.FileVersionInfo]::GetVersionInfo([string]$Definition.VersionFilePath).FileVersion)
            if ($rawVersion -match '(?<![0-9])([0-9]+(?:\.[0-9]+){1,3})(?![0-9])') {
                $version = $Matches[1]
            }
        }
    }
    catch {
        $version = $null
    }

    $mainLogPresent = $false
    $lastLocalActivityUtc = $null
    try {
        $mainLogPresent = [IO.File]::Exists([string]$Definition.MainLogPath)
        if ($mainLogPresent) {
            $lastLocalActivityUtc = [IO.File]::GetLastWriteTimeUtc([string]$Definition.MainLogPath)
        }
    }
    catch {
        $mainLogPresent = $false
        $lastLocalActivityUtc = $null
    }

    $localInterfaceAvailable = $null
    $localInterfaceStatus = 'NotRequired'
    if ([bool]$Definition.RequiresLocalInterface -and $installed) {
        $interfaceProbe = Test-EFCimNamespace -Namespace ([string]$Definition.LocalInterfaceName) -TimeoutSeconds $TimeoutSeconds
        if ([bool]$interfaceProbe.IsEvaluationError) {
            $localInterfaceStatus = 'CouldNotCheck'
        }
        else {
            $localInterfaceAvailable = [bool]$interfaceProbe.Exists
            $localInterfaceStatus = if ($localInterfaceAvailable) { 'Available' } else { 'Unavailable' }
        }
    }

    [pscustomobject][ordered]@{
        Installed               = $installed
        ServiceQuerySucceeded   = $serviceQuerySucceeded
        ServiceRegistryReadable = $serviceRegistryReadable
        ServiceStatus           = $serviceStatus
        StartupType             = $startupType
        Version                 = $version
        MainLogPresent          = $mainLogPresent
        LastLocalActivityUtc    = $lastLocalActivityUtc
        LocalInterfaceAvailable = $localInterfaceAvailable
        LocalInterfaceStatus    = $localInterfaceStatus
    }
}
