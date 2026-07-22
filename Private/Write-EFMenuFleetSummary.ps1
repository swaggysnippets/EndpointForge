function Write-EFMenuFleetSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Fleet,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Results for several computers' -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ([string]$Fleet.Summary) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Checked: {0}/{1}   Looks good: {2}   Needs attention: {3}   Urgent: {4}   Incomplete: {5}" -f
        $Fleet.SucceededCount, $Fleet.TargetCount, $Fleet.HealthyCount, $Fleet.WarningCount,
        $Fleet.CriticalCount, ($Fleet.IncompleteCount + $Fleet.FailedCount)) -NoColor:$NoColor -Width $Width

    foreach ($item in @($Fleet.Results)) {
        $label = switch ([string]$item.OverallStatus) {
            'Healthy' { 'LOOKS GOOD' }
            'Warning' { 'NEEDS ATTENTION' }
            'Critical' { 'URGENT ATTENTION' }
            default { 'COULD NOT CHECK EVERYTHING' }
        }
        $color = switch ([string]$item.OverallStatus) {
            'Healthy' { [ConsoleColor]::Green }
            'Critical' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Yellow }
        }
        Write-EFMenuLine -Text ("[{0}] {1} - score {2}/100, {3} item(s) need attention" -f
            $label, $item.ComputerName, $item.Score, $item.IssueCount) -Color $color -NoColor:$NoColor -Width $Width -Indent 2
    }
    foreach ($failure in @($Fleet.Failures)) {
        Write-EFMenuLine -Text ("[NOT CHECKED] {0}: {1}" -f $failure.ComputerName, $failure.Message) `
            -Color Red -NoColor:$NoColor -Width $Width -Indent 2
    }
    Write-EFMenuLine -Text ("What to do next: {0}" -f $Fleet.NextStep) -NoColor:$NoColor -Width $Width
}
