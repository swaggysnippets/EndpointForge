function Read-EFMenuInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Prompt
    )

    try {
        return Read-Host -Prompt $Prompt
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        throw
    }
    catch {
        throw [System.InvalidOperationException]::new(
            'Show-EFMenu requires an interactive PowerShell host. For unattended automation, use Get-EFEndpointSummary -NoProgress or Get-EFRemediationPlan -NoProgress.',
            $_.Exception
        )
    }
}
