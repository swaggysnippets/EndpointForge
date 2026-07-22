function Get-EFCertificateExpiryEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$StoreLocation,

        [Parameter(Mandatory)]
        [ValidateSet('My', 'Root', 'CA', 'AuthRoot', 'TrustedPeople', 'TrustedPublisher')]
        [string]$StoreName,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Fa-f0-9]{40}$')]
        [string]$Thumbprint,

        [ValidateRange(0, 3650)]
        [int]$MinimumDaysRemaining = 30
    )

    $locationValue = [Security.Cryptography.X509Certificates.StoreLocation]::$StoreLocation
    $store = [Security.Cryptography.X509Certificates.X509Store]::new($StoreName, $locationValue)
    $certificateMatches = $null
    try {
        $openFlags = [Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor
            [Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly
        $store.Open($openFlags)
        $certificateMatches = $store.Certificates.Find(
            [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $Thumbprint,
            $false
        )
        if ($certificateMatches.Count -gt 1) {
            throw 'Windows returned more than one certificate for the exact thumbprint.'
        }
        if ($certificateMatches.Count -eq 0) {
            return [pscustomobject]@{
                Found              = $false
                MeetsRequirement   = $false
                DaysRemaining      = $null
                IsCurrentlyValid   = $false
            }
        }

        $certificate = $certificateMatches[0]
        $now = [DateTime]::UtcNow
        $notBeforeUtc = $certificate.NotBefore.ToUniversalTime()
        $notAfterUtc = $certificate.NotAfter.ToUniversalTime()
        $daysRemaining = [math]::Floor(($notAfterUtc - $now).TotalDays)
        $currentlyValid = $notBeforeUtc -le $now -and $notAfterUtc -ge $now
        [pscustomobject]@{
            Found             = $true
            MeetsRequirement  = $currentlyValid -and $daysRemaining -ge $MinimumDaysRemaining
            DaysRemaining     = $daysRemaining
            IsCurrentlyValid  = $currentlyValid
        }
    }
    finally {
        if ($null -ne $certificateMatches) {
            foreach ($certificateMatch in $certificateMatches) { $certificateMatch.Dispose() }
        }
        $store.Close()
        $store.Dispose()
    }
}
