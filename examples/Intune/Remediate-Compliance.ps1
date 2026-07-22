$ErrorActionPreference = 'Stop'

try {
    Import-Module EndpointForge -MinimumVersion 0.6.0 -Force
    Set-EFConfiguration -LogPath '%ProgramData%\EndpointForge\endpointforge.jsonl'

    # The Intune deployment owner must review and maintain this allowlist. Assigning this
    # script with populated IDs is the independent change approval; the guided menu's APPLY
    # prompt is intentionally not used in unattended automation. The empty default is safe.
    $deploymentApprovedItemIds = @(
        # 'EF-FW-DOMAIN'
        # 'EF-FW-PRIVATE'
    )
    if ($deploymentApprovedItemIds.Count -eq 0) {
        Write-Output 'No checklist item IDs are approved in this deployment. No changes were made.'
        exit 0
    }

    $plan = Get-EFRemediationPlan -NoProgress
    $neededApprovedItemIds = @(
        $plan.Steps |
            Where-Object { $_.CanFixAutomatically -and $_.ControlId -in $deploymentApprovedItemIds } |
            ForEach-Object ControlId
    )
    if ($neededApprovedItemIds.Count -eq 0) {
        Write-Output 'No supported fixes are needed.'
        exit 0
    }

    # A fresh no-change preview is mandatory immediately before the unattended apply.
    $preview = Invoke-EFEndpointRemediation -ControlId $neededApprovedItemIds -WhatIf -Confirm:$false -NoProgress
    if ($preview.FailureCount -gt 0) {
        throw "The required preview had $($preview.FailureCount) error(s). No changes were applied."
    }
    $previewedItemIds = @($preview.Results | Where-Object Outcome -eq 'WhatIf' | ForEach-Object ControlId)
    if ($previewedItemIds.Count -eq 0) {
        Write-Output 'The approved settings already match. No changes were made.'
        exit 0
    }

    $report = Invoke-EFEndpointRemediation -ControlId $previewedItemIds -Confirm:$false -NoProgress

    Write-Output "Changed=$($report.ChangedCount); ObservedChanges=$($report.ObservedChangeCount); PartialChanges=$($report.PartialChangeCount); Remaining=$($report.RemainingCount); Failures=$($report.FailureCount); RebootRequired=$($report.RebootRequired)"
    if ($report.ExitCode -eq 0) { exit 0 }
    exit 1
}
catch {
    Write-Output "EndpointForge supported fix failed: $($_.Exception.Message)"
    exit 1
}
