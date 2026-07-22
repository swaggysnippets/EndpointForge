function Get-EFInstalledApplicationEvidence {
    [CmdletBinding()]
    param(
        [ValidateSet('Machine', 'CurrentUser', 'All')]
        [string]$Scope = 'Machine',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationName,

        [string]$Publisher,

        [string]$ProductCode,

        [ValidateSet('All', 'x64', 'x86', 'User')]
        [string]$Architecture = 'All',

        [ValidateRange(100, 10000)]
        [int]$MaximumRecords = 5000
    )

    $locations = @()
    if ($Scope -in @('Machine', 'All')) {
        if ([Environment]::Is64BitOperatingSystem) {
            $locations += [pscustomobject]@{
                Hive = [Microsoft.Win32.RegistryHive]::LocalMachine
                View = [Microsoft.Win32.RegistryView]::Registry64
                Scope = 'Machine'
                Architecture = 'x64'
            }
        }
        $locations += [pscustomobject]@{
            Hive = [Microsoft.Win32.RegistryHive]::LocalMachine
            View = [Microsoft.Win32.RegistryView]::Registry32
            Scope = 'Machine'
            Architecture = 'x86'
        }
    }
    if ($Scope -in @('CurrentUser', 'All')) {
        $locations += [pscustomobject]@{
            Hive = [Microsoft.Win32.RegistryHive]::CurrentUser
            View = [Microsoft.Win32.RegistryView]::Default
            Scope = 'CurrentUser'
            Architecture = 'User'
        }
    }

    $entries = [Collections.Generic.List[object]]::new()
    $errors = [Collections.Generic.List[string]]::new()
    $recordsScanned = 0
    $limitReached = $false
    $uninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $valueOptions = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    foreach ($location in $locations) {
        if ($Architecture -ne 'All' -and $location.Architecture -ne $Architecture) { continue }
        $baseKey = $null
        $uninstallKey = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($location.Hive, $location.View)
            $uninstallKey = $baseKey.OpenSubKey($uninstallPath, $false)
            if ($null -eq $uninstallKey) { continue }
            $remainingRecordBudget = $MaximumRecords - $recordsScanned
            if ($uninstallKey.SubKeyCount -gt $remainingRecordBudget) {
                $errors.Add("The installed-application scan exceeded its $MaximumRecords-record safety limit.")
                $limitReached = $true
                continue
            }

            foreach ($subKeyName in @($uninstallKey.GetSubKeyNames())) {
                $recordsScanned++
                if ($recordsScanned -gt $MaximumRecords) {
                    $errors.Add("The installed-application scan exceeded its $MaximumRecords-record safety limit.")
                    $limitReached = $true
                    break
                }
                $entryKey = $null
                try {
                    $entryKey = $uninstallKey.OpenSubKey($subKeyName, $false)
                    if ($null -eq $entryKey) {
                        $errors.Add("$($location.Scope) $($location.Architecture): one uninstall record could not be opened.")
                        continue
                    }
                    $displayName = [string]$entryKey.GetValue('DisplayName', $null, $valueOptions)
                    if ([string]::IsNullOrWhiteSpace($displayName)) { continue }
                    if (-not [string]::Equals($displayName, $ApplicationName, [StringComparison]::OrdinalIgnoreCase)) { continue }
                    $entryPublisher = [string]$entryKey.GetValue('Publisher', $null, $valueOptions)
                    if (-not [string]::IsNullOrWhiteSpace($Publisher) -and
                        -not [string]::Equals($entryPublisher, $Publisher, [StringComparison]::OrdinalIgnoreCase)) { continue }
                    if (-not [string]::IsNullOrWhiteSpace($ProductCode) -and
                        -not [string]::Equals([string]$subKeyName, $ProductCode, [StringComparison]::OrdinalIgnoreCase)) { continue }

                    $entries.Add([pscustomobject]@{
                        Name         = $displayName
                        Version      = [string]$entryKey.GetValue('DisplayVersion', $null, $valueOptions)
                        Publisher    = $entryPublisher
                        ProductCode  = [string]$subKeyName
                        Scope        = $location.Scope
                        Architecture = $location.Architecture
                    })
                }
                catch {
                    $errors.Add("$($location.Scope) $($location.Architecture): one uninstall record could not be read.")
                }
                finally {
                    if ($null -ne $entryKey) { $entryKey.Dispose() }
                }
            }
        }
        catch {
            $errors.Add("$($location.Scope) $($location.Architecture): the uninstall registry view could not be read.")
        }
        finally {
            if ($null -ne $uninstallKey) { $uninstallKey.Dispose() }
            if ($null -ne $baseKey) { $baseKey.Dispose() }
        }
        if ($limitReached) { break }
    }

    [pscustomobject]@{
        Entries     = @($entries)
        DataStatus  = if ($errors.Count -eq 0) { 'Complete' } else { 'Partial' }
        ErrorCount  = $errors.Count
        Errors      = @($errors)
        RecordsScanned = $recordsScanned
    }
}
