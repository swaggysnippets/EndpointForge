function Test-EFDnsResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 3000
    )

    $checkScript = {
        param($InputData)

        try {
            $addresses = @([Net.Dns]::GetHostAddresses([string]$InputData.HostName))
            [pscustomobject]@{
                Resolved          = $addresses.Count -gt 0
                FailureReason     = if ($addresses.Count -gt 0) { 'None' } else { 'NoRecords' }
                IsEvaluationError = $false
            }
        }
        catch [Net.Sockets.SocketException] {
            $socketError = $_.Exception.SocketErrorCode
            $isDefiniteMissingName = $socketError -in @(
                [Net.Sockets.SocketError]::HostNotFound,
                [Net.Sockets.SocketError]::NoData
            )
            [pscustomobject]@{
                Resolved          = $false
                FailureReason     = if ($isDefiniteMissingName) { 'NameNotFound' } else { [string]$socketError }
                IsEvaluationError = -not $isDefiniteMissingName
            }
        }
    }

    $absoluteHostName = $HostName.TrimEnd([char]'.') + '.'
    Invoke-EFIsolatedCheck -ScriptBlock $checkScript -InputData @{ HostName = $absoluteHostName } `
        -TimeoutMilliseconds $TimeoutMilliseconds -StartupAllowanceMilliseconds 3000 `
        -Activity 'The DNS resolution check'
}
