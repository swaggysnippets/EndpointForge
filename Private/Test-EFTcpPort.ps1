function Test-EFTcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [ValidateRange(100, 10000)]
        [int]$TimeoutMilliseconds = 3000
    )

    $client = [Net.Sockets.TcpClient]::new()
    $waitHandle = $null
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    try {
        try {
            $connection = $client.BeginConnect($HostName, $Port, $null, $null)
            $waitHandle = $connection.AsyncWaitHandle
            if (-not $waitHandle.WaitOne($TimeoutMilliseconds, $false)) {
                return [pscustomobject]@{
                    Connected           = $false
                    FailureReason       = 'TimedOut'
                    IsEvaluationError   = $false
                    ElapsedMilliseconds = [int]$stopwatch.ElapsedMilliseconds
                }
            }

            $client.EndConnect($connection)
            return [pscustomobject]@{
                Connected           = [bool]$client.Connected
                FailureReason       = if ($client.Connected) { 'None' } else { 'ConnectionFailed' }
                IsEvaluationError   = $false
                ElapsedMilliseconds = [int]$stopwatch.ElapsedMilliseconds
            }
        }
        catch [Net.Sockets.SocketException] {
            $socketError = $_.Exception.SocketErrorCode
            $nameResolutionErrors = @(
                [Net.Sockets.SocketError]::HostNotFound,
                [Net.Sockets.SocketError]::NoData,
                [Net.Sockets.SocketError]::NoRecovery,
                [Net.Sockets.SocketError]::TryAgain
            )
            $expectedConnectionFailures = @(
                [Net.Sockets.SocketError]::AddressNotAvailable,
                [Net.Sockets.SocketError]::ConnectionAborted,
                [Net.Sockets.SocketError]::ConnectionRefused,
                [Net.Sockets.SocketError]::ConnectionReset,
                [Net.Sockets.SocketError]::HostDown,
                [Net.Sockets.SocketError]::HostUnreachable,
                [Net.Sockets.SocketError]::NetworkDown,
                [Net.Sockets.SocketError]::NetworkUnreachable,
                [Net.Sockets.SocketError]::TimedOut
            )

            return [pscustomobject]@{
                Connected           = $false
                FailureReason       = if ($socketError -in $nameResolutionErrors) { 'NameResolutionFailed' } else { [string]$socketError }
                IsEvaluationError   = $socketError -notin $nameResolutionErrors -and $socketError -notin $expectedConnectionFailures
                ElapsedMilliseconds = [int]$stopwatch.ElapsedMilliseconds
            }
        }
    }
    finally {
        $stopwatch.Stop()
        if ($null -ne $waitHandle) {
            $waitHandle.Close()
        }
        $client.Close()
    }
}
