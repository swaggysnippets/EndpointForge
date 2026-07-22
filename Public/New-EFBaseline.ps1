function New-EFBaseline {
    <#
    .SYNOPSIS
    Creates a validated starter EndpointForge checklist.

    .DESCRIPTION
    A checklist is a list of things you expect to be true, such as a Windows setting,
    required file, recent event, or available network service; scripts call it a
    baseline. This command copies a maintained starter template, validates it, and writes
    UTF-8 JSON plus its schema. It does not apply the checklist or change Windows. A
    PowerShell WhatIf preview creates no files, and existing files require Force.

    .PARAMETER Name
    A stable organization checklist name such as Contoso.Workstation.

    .PARAMETER Path
    The output JSON path. A directory path writes <Name>.json inside that directory.

    .PARAMETER Description
    A plain-language purpose and scope for the checklist.

    .PARAMETER Version
    The semantic version for the new checklist.

    .PARAMETER Template
    Starter includes firewall, UAC, and Windows Update controls;
    EnterpriseRecommended includes every built-in setting; AuditOnly includes only
    BitLocker, Secure Boot, and TPM checks. EverydayChecks creates four report-only,
    edit-before-use examples for a file, text log, Windows event, and TCP connection.

    .PARAMETER Force
    Replaces an existing checklist file.

    .EXAMPLE
    New-EFBaseline -Name Contoso.Workstation -Template Starter -Path .\baselines

    .EXAMPLE
    New-EFBaseline -Name Contoso.Audit -Template AuditOnly -Path .\Contoso.Audit.json -WhatIf

    .EXAMPLE
    New-EFBaseline -Name Contoso.Operations -Template EverydayChecks -Path .\checklists

    Creates editable everyday check examples. Replace every sample target before use.

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

        [ValidateSet('Starter', 'EnterpriseRecommended', 'AuditOnly', 'EverydayChecks')]
        [string]$Template = 'Starter',

        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        $Description = "$Name EndpointForge checklist. Review it before use."
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

    if ($Template -eq 'EverydayChecks') {
        $examplePath = Join-Path $script:ModuleRoot 'examples\EverydayChecks.json'
        $sourceBaseline = Get-EFBaseline -Path $examplePath
        $controlIds = @($sourceBaseline.Controls.Id)
    }
    else {
        $sourceBaseline = Get-EFBaseline -Name EnterpriseRecommended
        $controlIds = switch ($Template) {
            'Starter' { @('EF-FW-DOMAIN', 'EF-FW-PRIVATE', 'EF-FW-PUBLIC', 'EF-UAC-ENABLED', 'EF-WUA-NOT-DISABLED') }
            'AuditOnly' { @('EF-BITLOCKER-OS', 'EF-SECUREBOOT', 'EF-TPM-READY') }
            default { @($sourceBaseline.Controls.Id) }
        }
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

    if (-not $PSCmdlet.ShouldProcess($targetPath, "Create $Template EndpointForge checklist")) {
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
            $(if ($Template -eq 'EverydayChecks') {
                "Replace every sample file path, search text, event source and ID, host, and port before use: $targetPath"
            } else {
                "Edit and review: $targetPath"
            })
            "Validate: Test-EFBaseline -Path '$targetPath'"
            "Plan: Get-EFRemediationPlan -Baseline '$targetPath'"
        )
    }
}
