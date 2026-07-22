function Get-EFConsoleWidth {
    [CmdletBinding()]
    param()

    $width = 80
    try {
        if ($null -ne $Host.UI -and $null -ne $Host.UI.RawUI) {
            $candidate = [int]$Host.UI.RawUI.WindowSize.Width
            if ($candidate -gt 0) {
                $width = $candidate
            }
        }
    }
    catch {
        $width = 80
    }

    return [math]::Min(120, [math]::Max(40, $width))
}
