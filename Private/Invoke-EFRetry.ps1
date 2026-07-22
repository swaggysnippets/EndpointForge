function Invoke-EFRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$Operation = 'operation',

        [ValidateRange(0, 10)]
        [int]$RetryCount = $script:EFConfiguration.RetryCount,

        [ValidateRange(0, 60)]
        [int]$DelaySeconds = $script:EFConfiguration.RetryDelaySeconds
    )

    $attempt = 0
    while ($true) {
        try {
            return & $ScriptBlock
        }
        catch {
            if ($attempt -ge $RetryCount) {
                throw
            }

            $attempt++
            Write-EFLog -Level Warning -Message "$Operation failed; retrying." -Data @{
                attempt = $attempt
                error   = $_.Exception.Message
            }
            if ($DelaySeconds -gt 0) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
}
