function Get-EFApprovedBaselineSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Baseline
    )

    [object]$approval = $null
    if (-not $script:EFBaselineIntegrityApprovals.TryGetValue($Baseline, [ref]$approval)) {
        return $null
    }

    $currentSourceJson = ConvertTo-EFBaselineSourceJson -Baseline $Baseline
    if ($currentSourceJson -cne [string]$approval.SourceJson) {
        return $null
    }

    try {
        $snapshot = ([string]$approval.SourceJson) | ConvertFrom-Json -ErrorAction Stop
        Assert-EFBaseline -Baseline $snapshot
        return $snapshot
    }
    catch {
        # Module-owned approval state should always remain parseable and valid. Fail
        # closed if process state corruption or an unexpected runtime failure occurs.
        return $null
    }
}
