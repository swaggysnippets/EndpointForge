function Get-EFInstalledSoftware {
    <#
    .SYNOPSIS
    Gets installed software from Windows uninstall registry entries.

    .DESCRIPTION
    Reads machine and/or current-user uninstall keys. It deliberately avoids the
    Win32_Product class, which can be slow and trigger Windows Installer consistency
    checks. Duplicate entries are normalized and removed.

    .PARAMETER Scope
    Selects Machine, CurrentUser, or All registry scopes. Under Intune, scheduled tasks,
    or another SYSTEM host, CurrentUser means the SYSTEM profile rather than the signed-in
    interactive user.

    .PARAMETER IncludeSystemComponents
    Includes entries marked as system components by their installer.

    .PARAMETER Name
    Filters display names with PowerShell wildcard syntax.

    .PARAMETER Publisher
    Filters publishers with PowerShell wildcard syntax.

    .PARAMETER Architecture
    Filters x64, x86, or per-user entries.

    .PARAMETER IncludeUninstallCommand
    Includes uninstall command lines. They are omitted by default because they can
    contain organization-specific paths or installer tokens.

    .EXAMPLE
    Get-EFInstalledSoftware | Where-Object Name -like '*7-Zip*'

    .EXAMPLE
    Get-EFInstalledSoftware -Name '*Microsoft*' -Architecture x64

    .OUTPUTS
    EndpointForge.InstalledSoftware
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Machine', 'CurrentUser', 'All')]
        [string]$Scope = 'All',

        [switch]$IncludeSystemComponents,

        [ValidateNotNullOrEmpty()]
        [string]$Name = '*',

        [ValidateNotNullOrEmpty()]
        [string]$Publisher = '*',

        [ValidateSet('All', 'x64', 'x86', 'User')]
        [string]$Architecture = 'All',

        [switch]$IncludeUninstallCommand
    )

    $null = Test-EFWindows -Throw
    $locations = @()
    if ($Scope -in @('Machine', 'All')) {
        $locations += [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Machine'; Architecture = 'x64' }
        $locations += [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Machine'; Architecture = 'x86' }
    }
    if ($Scope -in @('CurrentUser', 'All')) {
        $locations += [pscustomobject]@{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'CurrentUser'; Architecture = 'User' }
    }

    $items = foreach ($location in $locations) {
        foreach ($entry in @(Get-ItemProperty -Path $location.Path -ErrorAction SilentlyContinue)) {
            $displayName = [string](Get-EFPropertyValue -InputObject $entry -Name 'DisplayName')
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                continue
            }
            $entryPublisher = [string](Get-EFPropertyValue -InputObject $entry -Name 'Publisher')
            if ($displayName -notlike $Name -or $entryPublisher -notlike $Publisher) {
                continue
            }
            if ($Architecture -ne 'All' -and $location.Architecture -ne $Architecture) {
                continue
            }
            if (-not $IncludeSystemComponents -and [int](Get-EFPropertyValue -InputObject $entry -Name 'SystemComponent' -Default 0) -eq 1) {
                continue
            }

            $installDate = $null
            $rawInstallDate = [string](Get-EFPropertyValue -InputObject $entry -Name 'InstallDate')
            if ($rawInstallDate -match '^\d{8}$') {
                try { $installDate = [DateTime]::ParseExact($rawInstallDate, 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture) }
                catch { $installDate = $null }
            }
            $estimatedSize = Get-EFPropertyValue -InputObject $entry -Name 'EstimatedSize'

            [pscustomobject]@{
                PSTypeName       = 'EndpointForge.InstalledSoftware'
                Name             = $displayName
                Version          = [string](Get-EFPropertyValue -InputObject $entry -Name 'DisplayVersion')
                Publisher        = $entryPublisher
                InstallDate      = $installDate
                InstallLocation  = [string](Get-EFPropertyValue -InputObject $entry -Name 'InstallLocation')
                Scope            = $location.Scope
                Architecture     = $location.Architecture
                ProductCode      = [string](Get-EFPropertyValue -InputObject $entry -Name 'PSChildName')
                EstimatedSizeMB  = if ($null -ne $estimatedSize) { [math]::Round([double]$estimatedSize / 1024, 2) } else { $null }
                UninstallString  = if ($IncludeUninstallCommand) { [string](Get-EFPropertyValue -InputObject $entry -Name 'UninstallString') } else { $null }
            }
        }
    }

    $seen = @{}
    @($items | Sort-Object Name, Version, Scope, Architecture) | Where-Object {
        $key = '{0}|{1}|{2}|{3}|{4}' -f $_.Name, $_.Version, $_.Publisher, $_.Scope, $_.Architecture
        if ($seen.ContainsKey($key)) { return $false }
        $seen[$key] = $true
        return $true
    }
}
