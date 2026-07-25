function Get-EFBaseline {
    <#
    .SYNOPSIS
    Loads a built-in or file-based Windows computer checklist.

    .DESCRIPTION
    A checklist is a list of things expected to be true, such as Windows settings,
    storage, applications, jobs, files, certificates, recent events, local Windows
    management information, local network placement, or an approved network service. PowerShell commands call it a baseline for compatibility. This
    command only loads and validates the JSON file. It does not read a target, perform a
    network-active check, check a setting, or change a computer. ListAvailable shows the
    checklists included with the module.

    .PARAMETER Name
    The built-in checklist name. EnterpriseRecommended is the default.

    .PARAMETER Path
    The path to a custom checklist JSON file. Review custom files before use because they
    choose which applications, jobs, local paths, event logs, certificates, management
    namespaces, accounts, update services, hosts, ports, and web addresses later checks can inspect or contact.

    .PARAMETER ExpectedSha256
    The approved SHA-256 hash for a custom checklist file. When supplied, EndpointForge
    reads the file once and verifies that exact byte sequence before parsing it. Hash-
    verified files and custom files loaded from an elevated session cannot pass through
    links or reparse points.

    .PARAMETER ListAvailable
    Lists information about every checklist included with the installed module.

    .EXAMPLE
    Get-EFBaseline -Name EnterpriseRecommended

    .EXAMPLE
    Get-EFBaseline -Path .\contoso-baseline.json

    .EXAMPLE
    Get-EFBaseline -ListAvailable

    .EXAMPLE
    Get-EFBaseline -Path .\checklists\Contoso.EverydayChecks.json

    Loads and validates an everyday-checklist file without running any of its checks.

    .EXAMPLE
    Get-EFBaseline -Path .\Contoso.json -ExpectedSha256 $approvedHash

    Loads the custom checklist only when its bytes match the approved SHA-256 hash.

    .OUTPUTS
    EndpointForge.Baseline or EndpointForge.BaselineInfo.

    .LINK
    New-EFBaseline

    .LINK
    Test-EFBaseline
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('EndpointForge.Baseline', 'EndpointForge.BaselineInfo')]
    param(
        [Parameter(ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [string]$Name = 'EnterpriseRecommended',

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(ParameterSetName = 'Path')]
        [ValidatePattern('^[A-Fa-f0-9]{64}$')]
        [string]$ExpectedSha256,

        [Parameter(Mandatory, ParameterSetName = 'List')]
        [switch]$ListAvailable
    )

    if ($ListAvailable) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot 'Data') -Filter '*.json' -File) {
            if ($file.Name -in @('Baseline.schema.json', 'PublicContract.v1.json')) {
                continue
            }
            try {
                $fileContent = Read-EFBaselineFile -Path $file.FullName
                $item = $fileContent.Text | ConvertFrom-Json -ErrorAction Stop
                Assert-EFBaseline -Baseline $item
                [pscustomobject]@{
                    PSTypeName    = 'EndpointForge.BaselineInfo'
                    Name          = [string]$item.Name
                    FormatVersion = [string](Get-EFPropertyValue -InputObject $item -Name 'FormatVersion' -Default '1.0')
                    Version       = [string]$item.Version
                    Description   = [string]$item.Description
                    ControlCount  = @($item.Controls).Count
                    Path          = $file.FullName
                }
            }
            catch {
                Write-Warning "Skipping invalid built-in baseline '$($file.Name)': $($_.Exception.Message)"
            }
        }
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        if ($Name -notmatch '^[A-Za-z0-9._-]+$') {
            throw [System.ArgumentException]::new("Baseline name '$Name' contains invalid characters.")
        }
        $resolvedPath = Join-Path (Join-Path $script:ModuleRoot 'Data') "$Name.json"
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new("Built-in baseline '$Name' was not found.")
        }
    }
    else {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new("Baseline file '$resolvedPath' was not found.")
        }
    }

    $requireDirectPath = $PSCmdlet.ParameterSetName -eq 'Path' -and (
        $PSBoundParameters.ContainsKey('ExpectedSha256') -or (Test-EFAdministrator)
    )
    $readArguments = @{
        Path              = $resolvedPath
        RequireDirectPath = $requireDirectPath
    }
    if ($PSBoundParameters.ContainsKey('ExpectedSha256')) {
        $readArguments.ExpectedSha256 = $ExpectedSha256
    }
    $fileContent = Read-EFBaselineFile @readArguments

    try {
        $baseline = $fileContent.Text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw [System.IO.InvalidDataException]::new("Baseline '$resolvedPath' is not valid JSON: $($_.Exception.Message)")
    }

    Assert-EFBaseline -Baseline $baseline
    if (-not (Test-EFPropertyPresent -InputObject $baseline -Name 'FormatVersion')) {
        $baseline | Add-Member -NotePropertyName FormatVersion -NotePropertyValue '1.0'
    }
    $baseline.PSObject.TypeNames.Insert(0, 'EndpointForge.Baseline')
    $baseline | Add-Member -NotePropertyName SourcePath -NotePropertyValue $resolvedPath -Force
    $baseline | Add-Member -NotePropertyName SourceSha256 -NotePropertyValue $fileContent.Sha256 -Force
    $integrityVerified = $PSCmdlet.ParameterSetName -eq 'Name' -or
        $PSBoundParameters.ContainsKey('ExpectedSha256')
    $integrityMethod = if ($PSCmdlet.ParameterSetName -eq 'Name') {
        'InstalledModulePackage'
    }
    elseif ($PSBoundParameters.ContainsKey('ExpectedSha256')) {
        'ExpectedSha256'
    }
    else {
        'UnverifiedCustomFile'
    }
    $baseline | Add-Member -NotePropertyName IntegrityVerified -NotePropertyValue $integrityVerified -Force
    $baseline | Add-Member -NotePropertyName IntegrityMethod -NotePropertyValue $integrityMethod -Force
    $baseline | Add-Member -NotePropertyName ControlCount -NotePropertyValue @($baseline.Controls).Count -Force
    $baseline | Add-Member -NotePropertyName RemediableCount -NotePropertyValue @($baseline.Controls | Where-Object Remediable).Count -Force
    if ($integrityVerified) {
        Register-EFBaselineIntegrityApproval -Baseline $baseline -Method $integrityMethod
    }
    return $baseline
}
