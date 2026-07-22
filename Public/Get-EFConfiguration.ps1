function Get-EFConfiguration {
    <#
    .SYNOPSIS
    Gets the active EndpointForge session configuration.

    .DESCRIPTION
    Returns a copy of the module-scoped logging and retry configuration. Configuration
    applies only to the current PowerShell process and never changes machine policy.

    .EXAMPLE
    Get-EFConfiguration
    #>
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        PSTypeName        = 'EndpointForge.Configuration'
        LogPath           = $script:EFConfiguration.LogPath
        LogLevel          = $script:EFConfiguration.LogLevel
        RetryCount        = $script:EFConfiguration.RetryCount
        RetryDelaySeconds = $script:EFConfiguration.RetryDelaySeconds
    }
}
