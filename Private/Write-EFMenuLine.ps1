function Write-EFMenuLine {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'The opt-in EndpointForge menu intentionally writes presentation-only host output.'
    )]
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text = '',

        [ConsoleColor]$Color = [ConsoleColor]::Gray,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80,

        [ValidateRange(0, 40)]
        [int]$Indent = 0
    )

    $disableColor = [bool]$NoColor -or -not [string]::IsNullOrEmpty($env:NO_COLOR)
    try {
        $disableColor = $disableColor -or [Console]::IsOutputRedirected
    }
    catch {
        Write-Verbose 'Console redirection state is unavailable; using the explicit color preference.'
    }

    $availableWidth = [math]::Max(10, $Width - $Indent)
    $prefix = ' ' * $Indent
    $logicalLines = @($Text -split "`r?`n", -1)
    foreach ($logicalLine in $logicalLines) {
        $remaining = [string]$logicalLine
        if ($remaining.Length -eq 0) {
            if ($disableColor) { Write-Host '' } else { Write-Host '' -ForegroundColor $Color }
            continue
        }

        while ($remaining.Length -gt $availableWidth) {
            $breakAt = $remaining.LastIndexOf(' ', $availableWidth)
            if ($breakAt -lt 1) {
                $breakAt = $availableWidth
            }
            $segment = $remaining.Substring(0, $breakAt).TrimEnd()
            if ($disableColor) { Write-Host ($prefix + $segment) } else { Write-Host ($prefix + $segment) -ForegroundColor $Color }
            $remaining = $remaining.Substring($breakAt).TrimStart()
        }

        if ($disableColor) { Write-Host ($prefix + $remaining) } else { Write-Host ($prefix + $remaining) -ForegroundColor $Color }
    }
}
