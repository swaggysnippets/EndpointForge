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
    Write-EFMenuLine -Text 'Checking only reads Windows settings. It does not change this PC.' `
        -Color Green -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Checklist: {0} {1} ({2} checks)" -f $Readiness.ChecklistName, `
        $Readiness.ChecklistVersion, $Readiness.ControlCount) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'A checklist is simply the list of expected Windows settings that this PC is compared with.' `
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
