function Invoke-EFControlRemediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Control
    )

    $type = [string](Get-EFPropertyValue -InputObject $Control -Name 'Type')
    $desiredValue = Get-EFPropertyValue -InputObject $Control -Name 'DesiredValue'

    switch ($type) {
        'Registry' {
            $path = [string](Get-EFPropertyValue -InputObject $Control -Name 'Path')
            $valueName = [string](Get-EFPropertyValue -InputObject $Control -Name 'ValueName')
            $valueType = [string](Get-EFPropertyValue -InputObject $Control -Name 'ValueType' -Default 'String')
            if ($valueType -notin @('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')) {
                throw "Registry value type '$valueType' is not supported."
            }
            if (-not (Test-Path -LiteralPath $path)) {
                $null = New-Item -Path $path -Force -ErrorAction Stop
            }
            $null = New-ItemProperty -LiteralPath $path -Name $valueName -Value $desiredValue `
                -PropertyType $valueType -Force -ErrorAction Stop
        }

        'Service' {
            $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
            $startupType = [string](Get-EFPropertyValue -InputObject $Control -Name 'StartupType')
            $status = [string](Get-EFPropertyValue -InputObject $Control -Name 'Status')
            if (-not [string]::IsNullOrWhiteSpace($startupType)) {
                Set-Service -Name $name -StartupType $startupType -ErrorAction Stop
            }
            if ($status -eq 'Running') {
                Start-Service -Name $name -ErrorAction Stop
            }
            elseif ($status -eq 'Stopped') {
                Stop-Service -Name $name -Force -ErrorAction Stop
            }
        }

        'FirewallProfile' {
            $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
            Set-NetFirewallProfile -Name $name -Enabled ([bool]$desiredValue) -ErrorAction Stop
        }

        'Defender' {
            $propertyName = [string](Get-EFPropertyValue -InputObject $Control -Name 'Property')
            if ($propertyName -ne 'RealTimeProtectionEnabled') {
                throw "Automatic remediation is not implemented for Defender property '$propertyName'."
            }
            Set-MpPreference -DisableRealtimeMonitoring (-not [bool]$desiredValue) -ErrorAction Stop
        }

        'WindowsOptionalFeature' {
            $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
            if ([string]$desiredValue -eq 'Enabled') {
                $null = Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart -ErrorAction Stop
            }
            elseif ([string]$desiredValue -eq 'Disabled') {
                $null = Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop
            }
            else {
                throw "Desired optional feature state '$desiredValue' is not supported."
            }
        }

        default {
            throw "Control type '$type' does not support automatic remediation."
        }
    }

    [pscustomobject]@{
        RebootRequired = [bool](Get-EFPropertyValue -InputObject $Control -Name 'RequiresReboot' -Default $false)
    }
}
