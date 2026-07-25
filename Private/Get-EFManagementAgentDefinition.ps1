function Get-EFManagementAgentDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Intune', 'ConfigurationManager', 'CCM', 'SCCM', 'ConfigMgr')]
        [string]$Agent
    )

    $canonicalAgent = if ($Agent -eq 'Intune') { 'Intune' } else { 'ConfigurationManager' }
    $commonApplicationData = [Environment]::GetFolderPath('CommonApplicationData')
    $windowsDirectory = [Environment]::GetFolderPath('Windows')

    if ($canonicalAgent -eq 'Intune') {
        return [pscustomobject][ordered]@{
            Agent                 = 'Intune'
            DisplayName           = 'Microsoft Intune Management Extension'
            ServiceName           = 'IntuneManagementExtension'
            ServiceRegistryPath   = 'SYSTEM\CurrentControlSet\Services\IntuneManagementExtension'
            MainLogPath           = [IO.Path]::Combine(
                $commonApplicationData,
                'Microsoft',
                'IntuneManagementExtension',
                'Logs',
                'IntuneManagementExtension.log'
            )
            VersionFilePath       = [IO.Path]::Combine(
                $commonApplicationData,
                'Microsoft',
                'IntuneManagementExtension',
                'Microsoft.Management.Services.IntuneWindowsAgent.exe'
            )
            RequiresLocalInterface = $false
            LocalInterfaceName    = $null
            AvailableActions      = @('StartAgentService', 'RestartAgentService')
        }
    }

    [pscustomobject][ordered]@{
        Agent                 = 'ConfigurationManager'
        DisplayName           = 'Microsoft Configuration Manager client (ConfigMgr, SCCM, or CCM)'
        ServiceName           = 'CcmExec'
        ServiceRegistryPath   = 'SYSTEM\CurrentControlSet\Services\CcmExec'
        MainLogPath           = [IO.Path]::Combine($windowsDirectory, 'CCM', 'Logs', 'CcmExec.log')
        VersionFilePath       = [IO.Path]::Combine($windowsDirectory, 'CCM', 'CcmExec.exe')
        RequiresLocalInterface = $true
        LocalInterfaceName    = 'root\ccm'
        AvailableActions      = @(
            'StartAgentService',
            'RestartAgentService',
            'RequestMachinePolicy',
            'EvaluateMachinePolicy'
        )
    }
}
