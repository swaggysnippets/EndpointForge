function Write-EFMenuReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Readiness,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    $status = [string](Get-EFPropertyValue -InputObject $Readiness -Name 'Status' -Default 'Unknown')
    $statusColor = switch ($status) {
        'Ready' { [ConsoleColor]::Green }
        'Limited' { [ConsoleColor]::Yellow }
        'Blocked' { [ConsoleColor]::Red }
        default { [ConsoleColor]::Gray }
    }

    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Before you begin' -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("[{0}] {1}" -f $status.ToUpperInvariant(), [string]$Readiness.Summary) `
        -Color $statusColor -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Checking does not change this PC. A TCP item can make one brief network connection that may be recorded.' `
        -Color Green -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Checklist: {0} {1} ({2} checks)" -f $Readiness.ChecklistName, `
        $Readiness.ChecklistVersion, $Readiness.ControlCount) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'A checklist is a list of things expected to be true, such as settings, files, recent events, and network availability.' `
        -NoColor:$NoColor -Width $Width -Indent 2

    foreach ($check in @($Readiness.Checks)) {
        $checkStatus = [string](Get-EFPropertyValue -InputObject $check -Name 'Status' -Default 'Unknown')
        $checkColor = switch ($checkStatus) {
            'Ready' { [ConsoleColor]::Green }
            'Warning' { [ConsoleColor]::Yellow }
            'Blocked' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Gray }
        }
        Write-EFMenuLine -Text ("[{0}] {1}: {2}" -f $checkStatus.ToUpperInvariant(), $check.Name, $check.PlainLanguage) `
            -Color $checkColor -NoColor:$NoColor -Width $Width -Indent 2
    }

    Write-EFMenuLine -Text ("Next: {0}" -f $Readiness.NextStep) -NoColor:$NoColor -Width $Width
}
