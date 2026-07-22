function Set-EFConfiguration {
    <#
    .SYNOPSIS
    Configures EndpointForge logging and retry behavior for the current session.

    .DESCRIPTION
    Updates module-scoped configuration without writing to the registry or a profile.
    Logs use newline-delimited JSON (JSONL) so endpoint management systems can ingest
    one structured event per line.

    .PARAMETER LogPath
    The JSONL log file path. Environment variables such as %ProgramData% are expanded
    when an event is written. Use DisableFileLogging to clear the path.

    .PARAMETER LogLevel
    The minimum file-log level: Debug, Information, Warning, or Error.

    .PARAMETER RetryCount
    The number of retry attempts used by transient read operations.

    .PARAMETER RetryDelaySeconds
    The delay between retry attempts.

    .PARAMETER DisableFileLogging
    Clears LogPath and disables JSONL file logging for the current process.

    .PARAMETER Reset
    Restores all settings to their module defaults.

    .PARAMETER PassThru
    Returns the updated EndpointForge configuration object.

    .EXAMPLE
    Set-EFConfiguration -LogPath '%ProgramData%\EndpointForge\endpointforge.jsonl' -LogLevel Information

    .EXAMPLE
    Set-EFConfiguration -Reset

    .OUTPUTS
    EndpointForge.Configuration when PassThru is specified.

    .LINK
    Get-EFConfiguration
    #>
    [CmdletBinding(DefaultParameterSetName = 'Set', SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(ParameterSetName = 'Set')]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [Parameter(ParameterSetName = 'Set')]
        [ValidateSet('Debug', 'Information', 'Warning', 'Error')]
        [string]$LogLevel,

        [Parameter(ParameterSetName = 'Set')]
        [ValidateRange(0, 10)]
        [int]$RetryCount,

        [Parameter(ParameterSetName = 'Set')]
        [ValidateRange(0, 60)]
        [int]$RetryDelaySeconds,

        [Parameter(ParameterSetName = 'Set')]
        [switch]$DisableFileLogging,

        [Parameter(Mandatory, ParameterSetName = 'Reset')]
        [switch]$Reset,

        [switch]$PassThru
    )

    $operation = if ($Reset) { 'Reset configuration' } else { 'Update configuration' }
    if (-not $PSCmdlet.ShouldProcess('EndpointForge session configuration', $operation)) {
        if ($PassThru) {
            Get-EFConfiguration
        }
        return
    }

    if ($Reset) {
        $script:EFConfiguration.LogPath = $null
        $script:EFConfiguration.LogLevel = 'Information'
        $script:EFConfiguration.RetryCount = 2
        $script:EFConfiguration.RetryDelaySeconds = 2
    }
    else {
        if ($PSBoundParameters.ContainsKey('LogPath')) {
            $script:EFConfiguration.LogPath = $LogPath
        }
        if ($PSBoundParameters.ContainsKey('LogLevel')) {
            $script:EFConfiguration.LogLevel = $LogLevel
        }
        if ($PSBoundParameters.ContainsKey('RetryCount')) {
            $script:EFConfiguration.RetryCount = $RetryCount
        }
        if ($PSBoundParameters.ContainsKey('RetryDelaySeconds')) {
            $script:EFConfiguration.RetryDelaySeconds = $RetryDelaySeconds
        }
        if ($DisableFileLogging) {
            $script:EFConfiguration.LogPath = $null
        }
    }

    if ($PassThru) {
        Get-EFConfiguration
    }
}
