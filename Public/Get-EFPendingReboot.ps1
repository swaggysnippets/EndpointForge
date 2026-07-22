function Get-EFPendingReboot {
    <#
    .SYNOPSIS
    Determines whether Windows reports a pending restart.

    .DESCRIPTION
    Checks servicing, Windows Update, file rename, installer, and computer rename
    indicators. The command is read-only and returns the individual reasons.

    .EXAMPLE
    $reboot = Get-EFPendingReboot
    if ($reboot.IsRebootPending) { $reboot.Reasons }
    #>
    [CmdletBinding()]
    param()

    $null = Test-EFWindows -Throw
    $errors = [Collections.Generic.List[string]]::new()
    $indicators = [ordered]@{
        ComponentBasedServicing = $false
        WindowsUpdate           = $false
        PendingFileRename       = $false
        UpdateExeVolatile       = $false
        PendingComputerRename   = $false
    }

    $nativeRegistry = $null
    try {
        $nativeView = if ([Environment]::Is64BitOperatingSystem) {
            [Microsoft.Win32.RegistryView]::Registry64
        }
        else { [Microsoft.Win32.RegistryView]::Registry32 }
        $nativeRegistry = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            $nativeView
        )
    }
    catch {
        $errors.Add("NativeSoftwareRegistry: $($_.Exception.Message)")
    }

    foreach ($registryIndicator in @(
        @{ Name = 'ComponentBasedServicing'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' },
        @{ Name = 'WindowsUpdate'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
    )) {
        $indicatorKey = $null
        try {
            if ($null -eq $nativeRegistry) { continue }
            $indicatorKey = $nativeRegistry.OpenSubKey($registryIndicator.Path, $false)
            $indicators[$registryIndicator.Name] = $null -ne $indicatorKey
        }
        catch {
            $errors.Add("$($registryIndicator.Name): $($_.Exception.Message)")
        }
        finally {
            if ($null -ne $indicatorKey) { $indicatorKey.Dispose() }
        }
    }

    try {
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction Stop
        $indicators.PendingFileRename = @($sessionManager.PendingFileRenameOperations).Count -gt 0
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Verbose 'The pending file rename indicator is absent.'
    }
    catch [System.Management.Automation.PSArgumentException] {
        Write-Verbose 'The pending file rename indicator is absent.'
    }
    catch {
        $errors.Add("PendingFileRename: $($_.Exception.Message)")
    }

    $updatesKey = $null
    try {
        if ($null -ne $nativeRegistry) {
            $updatesKey = $nativeRegistry.OpenSubKey('SOFTWARE\Microsoft\Updates', $false)
            if ($null -ne $updatesKey) {
                $volatile = $updatesKey.GetValue(
                    'UpdateExeVolatile',
                    $null,
                    [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                )
                if ($null -ne $volatile) { $indicators.UpdateExeVolatile = [int]$volatile -ne 0 }
            }
        }
    }
    catch {
        $errors.Add("UpdateExeVolatile: $($_.Exception.Message)")
    }
    finally {
        if ($null -ne $updatesKey) { $updatesKey.Dispose() }
        if ($null -ne $nativeRegistry) { $nativeRegistry.Dispose() }
    }

    try {
        $activeName = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop
        $configuredName = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$activeName) -or
            [string]::IsNullOrWhiteSpace([string]$configuredName)) {
            throw 'Windows returned an empty computer name.'
        }
        $indicators.PendingComputerRename = -not [string]::Equals($activeName, $configuredName, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        $errors.Add("PendingComputerRename: $($_.Exception.Message)")
    }

    $reasons = @($indicators.GetEnumerator() | Where-Object Value | ForEach-Object Key)
    $reasonSummary = if ($reasons.Count -eq 0) { 'None' } else { $reasons -join ', ' }
    [pscustomobject]@{
        PSTypeName       = 'EndpointForge.PendingReboot'
        ComputerName     = $env:COMPUTERNAME
        CheckedAtUtc     = [DateTime]::UtcNow
        IsRebootPending  = $reasons.Count -gt 0
        DetectionCount   = $reasons.Count
        DataStatus       = if ($errors.Count -eq 0) { 'Complete' } else { 'Partial' }
        ErrorCount       = $errors.Count
        Errors           = @($errors)
        ReasonSummary    = $reasonSummary
        Reasons          = $reasons
        Indicators       = [pscustomobject]$indicators
    }
}
