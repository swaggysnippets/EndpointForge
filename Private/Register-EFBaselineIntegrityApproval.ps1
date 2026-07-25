function Register-EFBaselineIntegrityApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Baseline,

        [Parameter(Mandatory)]
        [ValidateSet('InstalledModulePackage', 'ExpectedSha256')]
        [string]$Method
    )

    # The approval is keyed by reference identity in module-owned state. The source-only
    # snapshot also prevents a caller from modifying an approved object after it is loaded.
    $approval = [pscustomobject]@{
        Method     = $Method
        SourceJson = ConvertTo-EFBaselineSourceJson -Baseline $Baseline
    }
    $null = $script:EFBaselineIntegrityApprovals.Remove($Baseline)
    $script:EFBaselineIntegrityApprovals.Add($Baseline, $approval)
}
