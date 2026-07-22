function Test-EFWindows {
    [CmdletBinding()]
    param(
        [switch]$Throw
    )

    $isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    if (-not $isWindowsPlatform -and $Throw) {
        throw [System.PlatformNotSupportedException]::new(
            'EndpointForge endpoint commands require Windows. The module can be imported on other platforms for discovery and packaging.'
        )
    }

    return $isWindowsPlatform
}
