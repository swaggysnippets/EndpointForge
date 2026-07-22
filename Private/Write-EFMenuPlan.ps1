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
    Write-EFMenuLine -Text 'Remediation plan' -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -Color Gray -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Baseline: {0} {1}" -f $Plan.BaselineName, $Plan.BaselineVersion) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Automatic: {0}   Manual: {1}   Blocked: {2}   Potential restart: {3}" -f `
        $Plan.AutomaticCount, $Plan.ManualCount, $Plan.BlockedCount, $(if ($Plan.PotentialReboot) { 'Yes' } else { 'No' })) `
        -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ([string]$Plan.Summary) -NoColor:$NoColor -Width $Width

    $steps = @($Plan.Steps)
    if ($steps.Count -eq 0) {
        Write-EFMenuLine -Text '[OK] No remediation actions are currently needed.' -Color Green -NoColor:$NoColor -Width $Width -Indent 2
        return
    }

    foreach ($step in $steps) {
        $color = switch ([string]$step.Action) {
            'Automatic' { [ConsoleColor]::Yellow }
            'Manual' { [ConsoleColor]::Yellow }
            'Blocked' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Gray }
        }
        Write-EFMenuLine -Text ("[{0}] {1} - {2}" -f ([string]$step.Action).ToUpperInvariant(), $step.ControlId, $step.Title) `
            -Color $color -NoColor:$NoColor -Width $Width -Indent 2
        Write-EFMenuLine -Text ("Current: {0}   Desired: {1}" -f `
            (ConvertTo-EFMenuValue -InputObject $step.CurrentValue), (ConvertTo-EFMenuValue -InputObject $step.DesiredValue)) `
            -NoColor:$NoColor -Width $Width -Indent 4
        if ($step.RequiresElevation -or $step.RequiresReboot) {
            Write-EFMenuLine -Text ("Impact: {0}{1}" -f `
                $(if ($step.RequiresElevation) { 'Administrator required' } else { 'No elevation' }), `
                $(if ($step.RequiresReboot) { '; restart may be required' } else { '' })) `
                -NoColor:$NoColor -Width $Width -Indent 4
        }
        if ($step.Action -in @('Manual', 'Blocked')) {
            Write-EFMenuLine -Text ("Next: {0}" -f $step.RecommendedAction) -NoColor:$NoColor -Width $Width -Indent 4
        }
    }
}
