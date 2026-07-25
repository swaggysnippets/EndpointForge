[CmdletBinding()]
param(
    [string]$ModuleVersion,

    [string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModuleVersion)) {
    $ModuleVersion = (Test-ModuleManifest (Join-Path $projectRoot 'EndpointForge.psd1') -ErrorAction Stop).Version.ToString()
}
$expectedVersion = [version]$ModuleVersion
if ($expectedVersion.Major -lt 1) {
    throw 'Managed certification evidence is a stable 1.x release gate.'
}
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $projectRoot "release-evidence\v$expectedVersion"
}
$resolvedEvidenceDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($EvidenceDirectory)
if (-not (Test-Path -LiteralPath $resolvedEvidenceDirectory -PathType Container)) {
    throw "Stable EndpointForge $expectedVersion requires checked-in certification evidence at '$resolvedEvidenceDirectory'."
}

$rings = @('Unmanaged', 'Intune', 'ConfigurationManager', 'CoManaged')
$editions = @('Desktop', 'Core')
$identities = @('StandardUser', 'Administrator', 'SYSTEM')
$requiredKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($ring in $rings) {
    foreach ($edition in $editions) {
        foreach ($identity in $identities) {
            $null = $requiredKeys.Add("$ring|$edition|$identity")
        }
    }
}

$evidenceFiles = @(Get-ChildItem -LiteralPath $resolvedEvidenceDirectory -Filter '*.json' -File)
if ($evidenceFiles.Count -lt $requiredKeys.Count) {
    throw "Stable certification requires at least $($requiredKeys.Count) JSON records: four rings, two PowerShell editions, and three execution identities."
}

$seenKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$records = [Collections.Generic.List[object]]::new()
foreach ($file in $evidenceFiles) {
    if ($file.Length -gt 1048576) {
        throw "Certification evidence '$($file.Name)' exceeds the 1 MiB safety limit."
    }
    try {
        $record = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Certification evidence '$($file.Name)' is not valid JSON: $($_.Exception.Message)"
    }

    $ring = [string]$record.Ring
    $edition = [string]$record.PowerShellEdition
    $identity = [string]$record.ExecutionIdentity
    $key = "$ring|$edition|$identity"
    if (-not $requiredKeys.Contains($key)) {
        throw "Certification evidence '$($file.Name)' has unsupported matrix key '$key'."
    }
    $null = $seenKeys.Add($key)
    if ([string]$record.EvidenceVersion -cne '1.0' -or
        [string]$record.ModuleVersion -cne $expectedVersion.ToString() -or
        -not [bool]$record.Passed -or
        -not [bool]$record.RuntimeSmokePassed -or
        [int]$record.ErrorCount -ne 0) {
        throw "Certification evidence '$($file.Name)' is not a passing EndpointForge $expectedVersion evidence record."
    }
    if ([string]::IsNullOrWhiteSpace([string]$record.WindowsCaption) -or
        [string]$record.WindowsBuild -notmatch '^\d+$' -or
        [string]$record.Architecture -notmatch '64' -or
        [string]::IsNullOrWhiteSpace([string]$record.PowerShellVersion)) {
        throw "Certification evidence '$($file.Name)' does not identify an exact 64-bit Windows and PowerShell host."
    }
    try {
        $null = [version]([string]$record.PowerShellVersion)
    }
    catch {
        throw "Certification evidence '$($file.Name)' has an invalid PowerShellVersion."
    }

    $expectIntune = $ring -in @('Intune', 'CoManaged')
    $expectConfigurationManager = $ring -in @('ConfigurationManager', 'CoManaged')
    if ([bool]$record.IntuneExpected -ne $expectIntune -or
        [bool]$record.IntuneDetected -ne $expectIntune -or
        [bool]$record.ConfigurationManagerExpected -ne $expectConfigurationManager -or
        [bool]$record.ConfigurationManagerDetected -ne $expectConfigurationManager) {
        throw "Certification evidence '$($file.Name)' does not match the required '$ring' agent state."
    }
    $expectedIntuneStatus = if ($expectIntune) { 'LooksReady' } else { 'NotDetected' }
    $expectedConfigurationManagerStatus = if ($expectConfigurationManager) { 'LooksReady' } else { 'NotDetected' }
    if ([string]$record.IntuneLocalStatus -cne $expectedIntuneStatus -or
        [string]$record.ConfigurationManagerLocalStatus -cne $expectedConfigurationManagerStatus) {
        throw "Certification evidence '$($file.Name)' does not contain complete healthy local-agent evidence for '$ring'."
    }

    $previews = @($record.WhatIfResults)
    if ($previews.Count -ne 2 -or @($previews | Where-Object {
        [string]$_.Outcome -cne 'WhatIf' -or [bool]$_.ChangeMayHaveOccurred
    }).Count -gt 0) {
        throw "Certification evidence '$($file.Name)' does not prove both no-change action previews."
    }
    $records.Add($record)
}

foreach ($requiredKey in $requiredKeys) {
    if (-not $seenKeys.Contains($requiredKey)) {
        throw "Required certification matrix entry '$requiredKey' is missing."
    }
}

foreach ($managedRing in @('Intune', 'ConfigurationManager', 'CoManaged')) {
    $approvedAdminRecords = @($records | Where-Object {
        [string]$_.Ring -ceq $managedRing -and
        [string]$_.ExecutionIdentity -ceq 'Administrator' -and
        [bool]$_.ChangingActionsRequested
    })
    $successfulAgents = @(
        $approvedAdminRecords |
            ForEach-Object { @($_.ChangingActionResults) } |
            Where-Object { [bool]$_.IsSuccessful } |
            Select-Object -ExpandProperty Agent -Unique
    )
    $requiredAgents = if ($managedRing -eq 'Intune') {
        @('Intune')
    }
    elseif ($managedRing -eq 'ConfigurationManager') {
        @('ConfigurationManager')
    }
    else {
        @('Intune', 'ConfigurationManager')
    }
    foreach ($requiredAgent in $requiredAgents) {
        if ($requiredAgent -notin $successfulAgents) {
            throw "The '$managedRing' Administrator evidence does not contain a successful approved $requiredAgent action."
        }
    }
}

[pscustomobject]@{
    PSTypeName       = 'EndpointForge.ManagedCertificationValidation'
    ModuleVersion    = $expectedVersion.ToString()
    EvidenceVersion  = '1.0'
    EvidenceRecords  = $records.Count
    Rings            = $rings.Count
    PowerShellHosts  = $editions.Count
    Identities       = $identities.Count
    IsValid          = $true
}
