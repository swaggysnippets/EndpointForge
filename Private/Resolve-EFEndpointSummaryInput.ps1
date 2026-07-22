function Resolve-EFEndpointSummaryInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [ValidateNotNullOrEmpty()]
        [string]$Label = 'Input'
    )

    if ($null -eq $InputObject) {
        throw [System.ArgumentNullException]::new($Label, "$Label must contain a completed EndpointForge computer check.")
    }

    $candidate = $InputObject
    if ($candidate -is [System.IO.FileInfo]) {
        $candidate = $candidate.FullName
    }

    if ($candidate -is [string]) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            throw [System.ArgumentException]::new("$Label path must not be empty.")
        }
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate)
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new("$Label report file was not found: $resolvedPath", $resolvedPath)
        }
        if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.json') {
            throw [System.ArgumentException]::new("$Label must be an EndpointForge JSON report file ending in .json.")
        }
        try {
            $candidate = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw [System.IO.InvalidDataException]::new("$Label report file is not valid JSON: $($_.Exception.Message)", $_.Exception)
        }
    }

    if ($candidate -is [System.Array]) {
        if ($candidate.Count -ne 1) {
            throw [System.IO.InvalidDataException]::new("$Label must contain one computer check, but the report contains $($candidate.Count).")
        }
        $candidate = $candidate[0]
    }

    for ($depth = 0; $depth -lt 3; $depth++) {
        if ($null -eq $candidate) { break }
        if ((Test-EFPropertyPresent -InputObject $candidate -Name 'Health') -and
            (Test-EFPropertyPresent -InputObject $candidate -Name 'Compliance')) {
            break
        }
        if (Test-EFPropertyPresent -InputObject $candidate -Name 'LastSummary') {
            $candidate = Get-EFPropertyValue -InputObject $candidate -Name 'LastSummary'
            continue
        }
        if (Test-EFPropertyPresent -InputObject $candidate -Name 'Summary') {
            $candidate = Get-EFPropertyValue -InputObject $candidate -Name 'Summary'
            continue
        }
        break
    }

    if ($null -eq $candidate) {
        throw [System.IO.InvalidDataException]::new("$Label does not contain a completed computer check. Run a check before comparing results.")
    }

    $health = Get-EFPropertyValue -InputObject $candidate -Name 'Health'
    $checklist = Get-EFPropertyValue -InputObject $candidate -Name 'Compliance'
    if ($null -eq $health -or $null -eq $checklist -or
        -not (Test-EFPropertyPresent -InputObject $health -Name 'Checks') -or
        -not (Test-EFPropertyPresent -InputObject $checklist -Name 'Results')) {
        throw [System.IO.InvalidDataException]::new(
            "$Label is not an EndpointForge computer check, menu session, menu report, or exported JSON report."
        )
    }

    $computerName = [string](Get-EFPropertyValue -InputObject $candidate -Name 'ComputerName')
    if ([string]::IsNullOrWhiteSpace($computerName)) {
        throw [System.IO.InvalidDataException]::new("$Label computer check does not identify the computer it came from.")
    }

    return $candidate
}
