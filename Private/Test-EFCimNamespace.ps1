function Test-EFCimNamespace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        [ValidateRange(1, 30)]
        [int]$TimeoutSeconds = 10
    )

    $namespacePattern = '^(?i:root)(?:\\[A-Za-z][A-Za-z0-9_]{0,127}){0,15}$'
    if ($Namespace -notmatch $namespacePattern) {
        throw [System.ArgumentException]::new(
            'Namespace must be root or an exact local path below root using only letters, numbers, and underscores.'
        )
    }

    $worker = {
        param($InputData)

        $namespacePath = [string]$InputData.Namespace
        $operationTimeoutSeconds = [int]$InputData.OperationTimeoutSeconds
        $cimManifestPath = [IO.Path]::Combine(
            [string]$PSHOME,
            'Modules',
            'CimCmdlets',
            'CimCmdlets.psd1'
        )
        if (-not [IO.File]::Exists($cimManifestPath)) {
            return [pscustomobject]@{
                ProviderAvailable = $false
                Exists            = $false
                IsEvaluationError = $true
                FailureReason     = 'ProviderUnavailable'
            }
        }

        try {
            Microsoft.PowerShell.Core\Import-Module -Name $cimManifestPath -Force -ErrorAction Stop
            $segments = @($namespacePath -split '\\')
            $currentNamespace = 'root'

            if ($segments.Count -gt 1) {
                for ($index = 1; $index -lt $segments.Count; $index++) {
                    $childName = [string]$segments[$index]
                    $namespaceMatches = @(CimCmdlets\Get-CimInstance -Namespace $currentNamespace `
                        -ClassName '__Namespace' -Filter "Name='$childName'" `
                        -OperationTimeoutSec $operationTimeoutSeconds -ErrorAction Stop)

                    if ($namespaceMatches.Count -eq 0) {
                        return [pscustomobject]@{
                            ProviderAvailable = $true
                            Exists            = $false
                            IsEvaluationError = $false
                            FailureReason     = 'NotFound'
                        }
                    }
                    if ($namespaceMatches.Count -ne 1 -or
                        -not [string]::Equals([string]$namespaceMatches[0].Name, $childName, [StringComparison]::OrdinalIgnoreCase)) {
                        return [pscustomobject]@{
                            ProviderAvailable = $true
                            Exists            = $false
                            IsEvaluationError = $true
                            FailureReason     = 'UnexpectedResult'
                        }
                    }

                    $currentNamespace = "$currentNamespace\$childName"
                }
            }

            $null = @(CimCmdlets\Get-CimInstance -Namespace $currentNamespace `
                -ClassName '__Namespace' -Filter "Name='__EndpointForgeAccessProbe__'" `
                -OperationTimeoutSec $operationTimeoutSeconds -ErrorAction Stop)

            return [pscustomobject]@{
                ProviderAvailable = $true
                Exists            = $true
                IsEvaluationError = $false
                FailureReason     = 'None'
            }
        }
        catch {
            $statusCodes = [Collections.Generic.List[int]]::new()
            $hresults = [Collections.Generic.List[int]]::new()
            $currentException = $_.Exception
            $exceptionDepth = 0
            while ($null -ne $currentException -and $exceptionDepth -lt 16) {
                if ($null -ne $currentException.PSObject.Properties['StatusCode']) {
                    try { $statusCodes.Add([int]$currentException.StatusCode) }
                    catch { Write-Verbose 'A CIM exception status code could not be normalized.' }
                }
                if ($null -ne $currentException.PSObject.Properties['HResult']) {
                    try { $hresults.Add([int]$currentException.HResult) }
                    catch { Write-Verbose 'A CIM exception result code could not be normalized.' }
                }
                $currentException = $currentException.InnerException
                $exceptionDepth++
            }

            if ($statusCodes.Contains(3) -or $hresults.Contains(-2147217394)) {
                return [pscustomobject]@{
                    ProviderAvailable = $true
                    Exists            = $false
                    IsEvaluationError = $false
                    FailureReason     = 'NotFound'
                }
            }

            $failureReason = if ($statusCodes.Contains(2) -or $hresults.Contains(-2147024891)) {
                'PermissionDenied'
            }
            else { 'ProviderError' }
            return [pscustomobject]@{
                ProviderAvailable = $true
                Exists            = $false
                IsEvaluationError = $true
                FailureReason     = $failureReason
            }
        }
    }

    try {
        $probe = Invoke-EFIsolatedCheck -ScriptBlock $worker -InputData @{
            Namespace               = $Namespace
            OperationTimeoutSeconds = $TimeoutSeconds
        } -TimeoutMilliseconds ($TimeoutSeconds * 1000) -StartupAllowanceMilliseconds 3000 `
            -Activity 'The local Windows management namespace check'
    }
    catch [TimeoutException] {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Exists            = $false
            IsEvaluationError = $true
            FailureReason     = 'TimedOut'
        }
    }
    catch {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Exists            = $false
            IsEvaluationError = $true
            FailureReason     = 'WorkerFailure'
        }
    }

    foreach ($propertyName in @('ProviderAvailable', 'Exists', 'IsEvaluationError', 'FailureReason')) {
        if (-not (Test-EFPropertyPresent -InputObject $probe -Name $propertyName)) {
            return [pscustomobject]@{
                ProviderAvailable = $true
                Exists            = $false
                IsEvaluationError = $true
                FailureReason     = 'UnexpectedResult'
            }
        }
    }
    if ($probe.ProviderAvailable -isnot [bool] -or $probe.Exists -isnot [bool] -or
        $probe.IsEvaluationError -isnot [bool] -or
        [string]$probe.FailureReason -notin @(
            'None', 'NotFound', 'ProviderUnavailable', 'PermissionDenied', 'ProviderError',
            'TimedOut', 'WorkerFailure', 'UnexpectedResult'
        )) {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Exists            = $false
            IsEvaluationError = $true
            FailureReason     = 'UnexpectedResult'
        }
    }

    $providerAvailable = [bool]$probe.ProviderAvailable
    $exists = [bool]$probe.Exists
    $isEvaluationError = [bool]$probe.IsEvaluationError
    $failureReason = [string]$probe.FailureReason
    $isConsistentResult = switch ($failureReason) {
        'None' {
            $providerAvailable -and $exists -and -not $isEvaluationError
        }
        'NotFound' {
            $providerAvailable -and -not $exists -and -not $isEvaluationError
        }
        'ProviderUnavailable' {
            -not $providerAvailable -and -not $exists -and $isEvaluationError
        }
        default {
            $providerAvailable -and -not $exists -and $isEvaluationError
        }
    }
    if (-not $isConsistentResult) {
        return [pscustomobject]@{
            ProviderAvailable = $true
            Exists            = $false
            IsEvaluationError = $true
            FailureReason     = 'UnexpectedResult'
        }
    }

    [pscustomobject]@{
        ProviderAvailable = $providerAvailable
        Exists            = $exists
        IsEvaluationError = $isEvaluationError
        FailureReason     = $failureReason
    }
}
