function Write-EFMenuManagementAgentHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Health,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    foreach ($item in @($Health)) {
        $statusLabel = switch ([string]$item.LocalStatus) {
            'LooksReady' { '[LOOKS READY]' }
            'NeedsAttention' { '[NEEDS ATTENTION]' }
            'NotDetected' { '[NOT DETECTED]' }
            default { '[COULD NOT CHECK]' }
        }
        $statusColor = switch ([string]$item.LocalStatus) {
            'LooksReady' { [ConsoleColor]::Green }
            'NeedsAttention' { [ConsoleColor]::Yellow }
            'NotDetected' { [ConsoleColor]::DarkYellow }
            default { [ConsoleColor]::Red }
        }
        Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
        Write-EFMenuLine -Text ("{0} {1}" -f $statusLabel, $item.DisplayName) -Color $statusColor -NoColor:$NoColor -Width $Width
        Write-EFMenuLine -Text ([string]$item.Summary) -NoColor:$NoColor -Width $Width -Indent 2
        if ([bool]$item.Installed) {
            $startupText = if ([string]::IsNullOrWhiteSpace([string]$item.StartupType)) { 'not available' } else { [string]$item.StartupType }
            $serviceText = if ([string]::IsNullOrWhiteSpace([string]$item.ServiceStatus)) { 'not available' } else { [string]$item.ServiceStatus }
            Write-EFMenuLine -Text ("Local service: {0}; startup: {1}" -f $serviceText, $startupText) -NoColor:$NoColor -Width $Width -Indent 2
            if ($null -ne $item.LastLocalActivityUtc) {
                Write-EFMenuLine -Text ("Last standard-log activity: {0}" -f ([DateTime]$item.LastLocalActivityUtc).ToLocalTime().ToString('g')) -NoColor:$NoColor -Width $Width -Indent 2
            }
            else {
                Write-EFMenuLine -Text 'Last standard-log activity: not available (the log can be missing or stored elsewhere)' -NoColor:$NoColor -Width $Width -Indent 2
            }
        }
        foreach ($finding in @($item.Findings)) {
            Write-EFMenuLine -Text ("Finding: {0}" -f $finding) -Color Yellow -NoColor:$NoColor -Width $Width -Indent 2
        }
        Write-EFMenuLine -Text ("Next step: {0}" -f $item.NextStep) -NoColor:$NoColor -Width $Width -Indent 2
    }
    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'This was a local-only check. It read no log lines, tenant or site details, device IDs, policies, applications, accounts, or server addresses.' -Color Green -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'A local Looks ready result does not prove that a cloud or site check-in succeeded.' -Color Yellow -NoColor:$NoColor -Width $Width
}
