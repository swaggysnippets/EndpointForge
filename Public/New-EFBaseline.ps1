function New-EFBaseline {
    <#
    .SYNOPSIS
    Creates a validated EndpointForge baseline JSON file.

    .DESCRIPTION
    Creates a safe starting baseline from a maintained template, validates it with the
    same runtime contract used by compliance commands, and writes UTF-8 without a BOM.
    The command supports WhatIf and never overwrites unless Force is specified.

    .PARAMETER Name
    A stable organization baseline name such as Contoso.Workstation.

    .PARAMETER Path
    The output JSON path. A directory path writes <Name>.json inside that directory.

    .PARAMETER Description
    A human-readable purpose and scope for the baseline.

    .PARAMETER Version
    The semantic version for the new baseline.

    .PARAMETER Template
    Starter includes firewall, UAC, and Windows Update controls;
    EnterpriseRecommended includes every built-in control; AuditOnly includes only
    BitLocker, Secure Boot, and TPM audit controls.

    .PARAMETER Force
    Replaces an existing baseline file.

    .EXAMPLE
    New-EFBaseline -Name Contoso.Workstation -Template Starter -Path .\baselines

    .EXAMPLE
    New-EFBaseline -Name Contoso.Audit -Template AuditOnly -Path .\Contoso.Audit.json -WhatIf

    .OUTPUTS
    EndpointForge.BaselineCreationResult
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')]
        [string]$Name,

        [string]$Path,

        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
        [string]$Version = '1.0.0',

        [ValidateSet('Starter', 'EnterpriseRecommended', 'AuditOnly')]
        [string]$Template = 'Starter',

        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        $Description = "$Name endpoint compliance baseline."
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $targetPath = Join-Path (Get-Location).Path "$Name.json"
    }
    else {
        $unresolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $treatAsDirectory = (Test-Path -LiteralPath $unresolvedPath -PathType Container) -or
            [string]::IsNullOrWhiteSpace([IO.Path]::GetExtension($unresolvedPath))
        $targetPath = if ($treatAsDirectory) { Join-Path $unresolvedPath "$Name.json" } else { $unresolvedPath }
    }

    if ([IO.Path]::GetExtension($targetPath) -ne '.json') {
        throw [System.ArgumentException]::new("Baseline path '$targetPath' must use the .json extension.")
    }
    if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
        throw [System.IO.IOException]::new("Baseline '$targetPath' already exists. Use -Force to replace it.")
    }

    $sourceBaseline = Get-EFBaseline -Name EnterpriseRecommended
    $controlIds = switch ($Template) {
        'Starter' { @('EF-FW-DOMAIN', 'EF-FW-PRIVATE', 'EF-FW-PUBLIC', 'EF-UAC-ENABLED', 'EF-WUA-NOT-DISABLED') }
        'AuditOnly' { @('EF-BITLOCKER-OS', 'EF-SECUREBOOT', 'EF-TPM-READY') }
        default { @($sourceBaseline.Controls.Id) }
    }
    $selectedControls = @($sourceBaseline.Controls | Where-Object Id -in $controlIds)
    $clonedControls = $selectedControls | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $baseline = [pscustomobject][ordered]@{
        '$schema'   = './EndpointForge.Baseline.schema.json'
        Name        = $Name
        Version     = $Version
        Description = $Description
        Controls    = @($clonedControls)
    }
    Assert-EFBaseline -Baseline $baseline

    if (-not $PSCmdlet.ShouldProcess($targetPath, "Create $Template EndpointForge baseline")) {
        return
    }

    $parent = Split-Path -Parent $targetPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
    }
    $schemaPath = Join-Path $parent 'EndpointForge.Baseline.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath) -or $Force) {
        Copy-Item -LiteralPath (Join-Path $script:ModuleRoot 'Data\Baseline.schema.json') `
            -Destination $schemaPath -Force:$Force -ErrorAction Stop
    }
    $json = ConvertTo-EFSerializableValue -InputObject $baseline | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($targetPath, $json, [Text.UTF8Encoding]::new($false))
    $createdBaseline = Get-EFBaseline -Path $targetPath

    [pscustomobject]@{
        PSTypeName   = 'EndpointForge.BaselineCreationResult'
        Name         = $Name
        Version      = $Version
        Template     = $Template
        Path         = $targetPath
        SchemaPath   = $schemaPath
        ControlCount = @($createdBaseline.Controls).Count
        Baseline     = $createdBaseline
        NextSteps    = @(
            "Edit and review: $targetPath"
            "Validate: Test-EFBaseline -Path '$targetPath'"
            "Plan: Get-EFRemediationPlan -Baseline '$targetPath'"
        )
    }
}
