function Write-EFMenuPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Safe fix plan - nothing has changed' -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -Color Gray -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Checklist: {0} {1}" -f $Plan.BaselineName, $Plan.BaselineVersion) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("EndpointForge can preview: {0}   You need to review: {1}   Could not check: {2}   Restart may be needed: {3}" -f `
        $Plan.AutomaticCount, $Plan.ManualCount, $Plan.BlockedCount, $(if ($Plan.PotentialReboot) { 'Yes' } else { 'No' })) `
        -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ([string]$Plan.Summary) -NoColor:$NoColor -Width $Width

    $steps = @($Plan.Steps)
    if ($steps.Count -eq 0) {
        Write-EFMenuLine -Text '[LOOKS GOOD] No supported fixes or manual actions are currently needed.' -Color Green -NoColor:$NoColor -Width $Width -Indent 2
        return
    }

    foreach ($step in $steps) {
        $color = switch ([string]$step.Action) {
            'Automatic' { [ConsoleColor]::Yellow }
            'Manual' { [ConsoleColor]::Yellow }
            'Blocked' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Gray }
        }
        $actionLabel = switch ([string]$step.Action) {
            'Automatic' { 'ENDPOINTFORGE CAN FIX' }
            'Manual' { 'YOU NEED TO REVIEW' }
            'Blocked' { 'COULD NOT CHECK' }
            'NotApplicable' { 'NOT USED ON THIS COMPUTER' }
            default { 'NO CHANGE NEEDED' }
        }
        Write-EFMenuLine -Text ("[{0}] {1}" -f $actionLabel, $step.Title) `
            -Color $color -NoColor:$NoColor -Width $Width -Indent 2
        if (-not [string]::IsNullOrWhiteSpace([string](Get-EFPropertyValue $step 'WhyItMatters' ''))) {
            Write-EFMenuLine -Text ("Why it matters: {0}" -f $step.WhyItMatters) -NoColor:$NoColor -Width $Width -Indent 4
        }
        Write-EFMenuLine -Text ("Found now: {0}   Expected: {1}" -f `
            (ConvertTo-EFMenuValue -InputObject $step.CurrentValue), (ConvertTo-EFMenuValue -InputObject $step.DesiredValue)) `
            -NoColor:$NoColor -Width $Width -Indent 4
        if ($step.Action -eq 'Automatic') {
            Write-EFMenuLine -Text ("What a supported fix would do: {0}" -f (Get-EFPropertyValue $step 'WhatWouldChange' 'EndpointForge would change the found value to the expected value after approval.')) -NoColor:$NoColor -Width $Width -Indent 4
            Write-EFMenuLine -Text ("Safety: Administrator permission is required{0}." -f $(if ($step.RequiresReboot) { '; a restart may be needed later, but EndpointForge will not restart Windows' } else { '' })) `
                -NoColor:$NoColor -Width $Width -Indent 4
        }
        if ($step.Action -in @('Manual', 'Blocked')) {
            $manualText = Get-EFPropertyValue $step 'ManualAction' $step.RecommendedAction
            Write-EFMenuLine -Text ("What you can do: {0}" -f $manualText) -NoColor:$NoColor -Width $Width -Indent 4
        }
    }
}
