function Test-EFHttpEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [uri]$Uri,

        [ValidateRange(100, 30000)]
        [int]$TimeoutMilliseconds = 5000,

        [ValidateSet('Head', 'Get')]
        [string]$Method = 'Head',

        [switch]$AllowRedirects
    )

    $checkScript = {
        param($InputData)

        $handler = $null
        $client = $null
        $cancellation = $null
        try {
            $null = Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
            $handler = [Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect = $false
            $handler.UseCookies = $false
            $handler.UseDefaultCredentials = $false
            $handler.Credentials = $null
            $handler.UseProxy = $true
            $handler.Proxy = $null
            $handler.DefaultProxyCredentials = $null
            $client = [Net.Http.HttpClient]::new($handler)
            $client.Timeout = [Threading.Timeout]::InfiniteTimeSpan
            $httpMethod = if ([string]$InputData.Method -eq 'Get') {
                [Net.Http.HttpMethod]::Get
            }
            else {
                [Net.Http.HttpMethod]::Head
            }
            $currentUri = [uri][string]$InputData.Uri
            $startingUri = $currentUri
            $cancellation = [Threading.CancellationTokenSource]::new([int]$InputData.TimeoutMilliseconds)

            for ($redirectCount = 0; $redirectCount -le 5; $redirectCount++) {
                $request = $null
                $response = $null
                try {
                    $request = [Net.Http.HttpRequestMessage]::new($httpMethod, $currentUri)
                    $response = $client.SendAsync(
                        $request,
                        [Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                        $cancellation.Token
                    ).GetAwaiter().GetResult()
                    $statusCode = [int]$response.StatusCode
                    $isRedirect = $statusCode -in @(301, 302, 303, 307, 308)
                    $location = $response.Headers.Location
                    if (-not [bool]$InputData.AllowRedirects -or -not $isRedirect -or $null -eq $location) {
                        return [pscustomobject]@{
                            Responded         = $true
                            StatusCode        = $statusCode
                            FailureReason     = 'None'
                            IsEvaluationError = $false
                        }
                    }
                    if ($redirectCount -ge 5) {
                        return [pscustomobject]@{
                            Responded         = $false
                            StatusCode        = $statusCode
                            FailureReason     = 'TooManyRedirects'
                            IsEvaluationError = $true
                        }
                    }

                    $nextUri = if ($location.IsAbsoluteUri) { $location } else { [uri]::new($currentUri, $location) }
                    if ($nextUri.AbsoluteUri.Length -gt 2048 -or
                        -not [string]::IsNullOrWhiteSpace($nextUri.UserInfo) -or
                        -not [string]::IsNullOrWhiteSpace($nextUri.Query) -or
                        -not [string]::IsNullOrWhiteSpace($nextUri.Fragment) -or
                        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($nextUri.AbsoluteUri)) {
                        return [pscustomobject]@{
                            Responded         = $false
                            StatusCode        = $statusCode
                            FailureReason     = 'UnsafeRedirectBlocked'
                            IsEvaluationError = $true
                        }
                    }
                    if ($nextUri.Scheme -ine $startingUri.Scheme -or
                        $nextUri.Host -ine $startingUri.Host -or $nextUri.Port -ne $startingUri.Port) {
                        return [pscustomobject]@{
                            Responded         = $false
                            StatusCode        = $statusCode
                            FailureReason     = 'CrossOriginRedirectBlocked'
                            IsEvaluationError = $true
                        }
                    }
                    $currentUri = $nextUri
                }
                finally {
                    if ($null -ne $response) { $response.Dispose() }
                    if ($null -ne $request) { $request.Dispose() }
                }
            }
        }
        catch [OperationCanceledException] {
            return [pscustomobject]@{
                Responded         = $false
                StatusCode        = $null
                FailureReason     = 'Timeout'
                IsEvaluationError = $false
            }
        }
        catch {
            $socketError = $null
            $webStatus = $null
            $currentError = $_.Exception
            while ($null -ne $currentError) {
                if ($currentError -is [Net.Sockets.SocketException]) {
                    $socketError = $currentError.SocketErrorCode
                    break
                }
                if ($currentError -is [Net.WebException]) { $webStatus = $currentError.Status }
                $currentError = $currentError.InnerException
            }
            $isDefiniteConnectionFailure = $socketError -in @(
                [Net.Sockets.SocketError]::ConnectionRefused,
                [Net.Sockets.SocketError]::TimedOut
            ) -or $webStatus -eq [Net.WebExceptionStatus]::Timeout
            return [pscustomobject]@{
                Responded         = $false
                StatusCode        = $null
                FailureReason     = if ($isDefiniteConnectionFailure) { 'ConnectionFailed' } else { 'RequestFailed' }
                IsEvaluationError = -not $isDefiniteConnectionFailure
            }
        }
        finally {
            if ($null -ne $client) { $client.Dispose() }
            if ($null -ne $handler) { $handler.Dispose() }
            if ($null -ne $cancellation) { $cancellation.Dispose() }
        }
    }

    Invoke-EFIsolatedCheck -ScriptBlock $checkScript -InputData @{
        Uri                 = $Uri.AbsoluteUri
        TimeoutMilliseconds = $TimeoutMilliseconds
        Method              = $Method
        AllowRedirects      = [bool]$AllowRedirects
    } -TimeoutMilliseconds $TimeoutMilliseconds -StartupAllowanceMilliseconds 3000 `
        -Activity 'The HTTP endpoint check'
}
