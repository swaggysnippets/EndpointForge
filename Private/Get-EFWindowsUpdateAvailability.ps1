function Get-EFWindowsUpdateAvailability {
    [CmdletBinding()]
    param(
        [ValidateRange(10, 600)]
        [int]$TimeoutSeconds = 120,

        [switch]$IncludeOptional,

        [switch]$IncludeDrivers
    )

    $checkScript = {
        param($InputData)

        $session = New-Object -ComObject 'Microsoft.Update.Session' -ErrorAction Stop
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true
        $searcher.CanAutomaticallyUpgradeService = $false

        $criteria = 'IsInstalled=0 and IsHidden=0'
        if (-not [bool]$InputData.IncludeDrivers) {
            $criteria += " and Type='Software'"
        }
        if (-not [bool]$InputData.IncludeOptional) {
            $criteria += ' and IsAssigned=1'
        }

        $searchResult = $searcher.Search($criteria)
        $warningCount = 0
        if ($null -ne $searchResult.PSObject.Properties['Warnings'] -and $null -ne $searchResult.Warnings) {
            $warningCount = [int]$searchResult.Warnings.Count
        }
        [pscustomobject]@{
            UpdateCount = [int]$searchResult.Updates.Count
            ResultCode  = [int]$searchResult.ResultCode
            WarningCount = $warningCount
        }
    }

    $result = Invoke-EFIsolatedCheck -ScriptBlock $checkScript -InputData @{
        IncludeOptional = [bool]$IncludeOptional
        IncludeDrivers  = [bool]$IncludeDrivers
    } -TimeoutMilliseconds ($TimeoutSeconds * 1000) -StartupAllowanceMilliseconds 3000 `
        -Activity 'The Windows Update availability check'

    if (-not (Test-EFPropertyPresent -InputObject $result -Name 'ResultCode') -or
        -not (Test-EFPropertyPresent -InputObject $result -Name 'WarningCount') -or
        -not (Test-EFPropertyPresent -InputObject $result -Name 'UpdateCount')) {
        throw [InvalidOperationException]::new('Windows Update returned an incomplete search result.')
    }
    if ([int]$result.ResultCode -ne 2 -or [int]$result.WarningCount -ne 0 -or [int]$result.UpdateCount -lt 0) {
        throw [InvalidOperationException]::new(
            "Windows Update returned an incomplete result (result code $($result.ResultCode), warning count $($result.WarningCount))."
        )
    }

    [pscustomobject]@{
        UpdateCount     = [int]$result.UpdateCount
        ResultCode      = [int]$result.ResultCode
        WarningCount    = [int]$result.WarningCount
        IncludeOptional = [bool]$IncludeOptional
        IncludeDrivers  = [bool]$IncludeDrivers
    }
}
