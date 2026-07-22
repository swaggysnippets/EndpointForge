function Write-EFMenuComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Comparison,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'What changed since the earlier check' -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Earlier: {0}   Latest: {1}" -f $Comparison.BeforeComputerName, $Comparison.AfterComputerName) `
        -NoColor:$NoColor -Width $Width

    if ($Comparison.DifferentComputer) {
        Write-EFMenuLine -Text '[IMPORTANT] These checks came from different computers. This is a side-by-side comparison, not a progress report.' `
            -Color Yellow -NoColor:$NoColor -Width $Width
    }
    if ($Comparison.ChecklistChanged) {
        Write-EFMenuLine -Text ("[IMPORTANT] The checklist changed from {0} {1} to {2} {3}. Results may differ because different settings were checked." -f `
            $Comparison.BeforeChecklistName, $Comparison.BeforeChecklistVersion,
            $Comparison.AfterChecklistName, $Comparison.AfterChecklistVersion) `
            -Color Yellow -NoColor:$NoColor -Width $Width
    }

    Write-EFMenuLine -Text ("Improved: {0}   New attention: {1}   Could not check: {2}   Same: {3}" -f `
        $Comparison.ImprovedCount, $Comparison.NewIssueCount, $Comparison.CouldNotCheckCount, $Comparison.UnchangedCount) `
        -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Overall score: {0} -> {1} ({2})" -f $Comparison.BeforeScore, $Comparison.AfterScore, `
        $(if ($Comparison.ScoreChange -gt 0) { "+$($Comparison.ScoreChange)" } else { [string]$Comparison.ScoreChange })) `
        -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Information available: {0}% -> {1}% ({2})" -f `
        $Comparison.BeforeCoveragePercent, $Comparison.AfterCoveragePercent,
        $(if ($Comparison.CoverageChange -gt 0) { "+$($Comparison.CoverageChange)" } else { [string]$Comparison.CoverageChange })) `
        -NoColor:$NoColor -Width $Width

    foreach ($change in @($Comparison.Changes | Where-Object Category -ne 'Unchanged')) {
        $label = switch ([string]$change.Category) {
            'Improved' { 'IMPROVED' }
            'NewIssue' { 'NEEDS ATTENTION' }
            'CouldNotCheck' { 'COULD NOT CHECK' }
            'NowAvailable' { 'NOW AVAILABLE' }
            'ChecklistChanged' { 'CHECKLIST CHANGED' }
            default { 'CHANGED' }
        }
        $color = switch ([string]$change.Category) {
            'Improved' { [ConsoleColor]::Green }
            'NewIssue' { [ConsoleColor]::Yellow }
            'CouldNotCheck' { [ConsoleColor]::Yellow }
            default { [ConsoleColor]::Gray }
        }
        Write-EFMenuLine -Text ("[{0}] {1}" -f $label, $change.Title) -Color $color -NoColor:$NoColor -Width $Width -Indent 2
        Write-EFMenuLine -Text ([string]$change.Explanation) -NoColor:$NoColor -Width $Width -Indent 4
    }

    Write-EFMenuLine -Text ("Summary: {0}" -f $Comparison.Summary) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("What to do next: {0}" -f $Comparison.NextStep) -NoColor:$NoColor -Width $Width
}
