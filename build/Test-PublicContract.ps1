[CmdletBinding()]
param(
    [string]$ModulePath,

    [string]$ContractPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $projectRoot 'EndpointForge.psd1'
}
if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $projectRoot 'Data\PublicContract.v1.json'
}
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
$resolvedContractPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ContractPath)

$contract = Get-Content -LiteralPath $resolvedContractPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -ErrorAction Stop
if ([string]$contract.ContractVersion -ne '1.0') {
    throw "Public contract '$resolvedContractPath' must declare ContractVersion 1.0."
}
if ([string]$contract.ChecklistFormatVersion -ne '1.0') {
    throw "Public contract '$resolvedContractPath' must declare ChecklistFormatVersion 1.0."
}

$expectedExitCodes = [ordered]@{
    '0' = 'Healthy, compliant, complete, or successful'
    '1' = 'Warning or attention required'
    '2' = 'Critical, noncompliant, or change available'
    '3' = 'Unknown, incomplete, blocked, or failed'
}
$actualExitCodeNames = @($contract.ExitCodes.PSObject.Properties.Name | Sort-Object)
if (($actualExitCodeNames -join "`n") -cne (@($expectedExitCodes.Keys | Sort-Object) -join "`n")) {
    throw 'The public contract exit-code keys must remain exactly 0, 1, 2, and 3.'
}
foreach ($exitCode in $expectedExitCodes.Keys) {
    if ([string]$contract.ExitCodes.$exitCode -cne [string]$expectedExitCodes[$exitCode]) {
        throw "The stable meaning for public exit code $exitCode changed."
    }
}

$expectedStatusVocabularies = [ordered]@{
    'EndpointForge.ControlResult.Status' = @('Compliant', 'NonCompliant', 'NotApplicable', 'Error')
    'EndpointForge.EndpointHealth.Checks.Status' = @('Healthy', 'Unhealthy', 'Unknown')
    'EndpointForge.EndpointHealth.Status' = @('Healthy', 'Warning', 'Critical', 'Unknown')
    'EndpointForge.EndpointSummary.OverallStatus' = @('Healthy', 'Warning', 'Critical', 'Incomplete')
    'EndpointForge.ComplianceReport.Status' = @('Compliant', 'NonCompliant', 'Incomplete')
    'EndpointForge.Collection.DataStatus' = @('Complete', 'Partial', 'Failed')
    'EndpointForge.EndpointReadiness.Status' = @('Ready', 'Limited', 'Blocked')
    'EndpointForge.ReadinessCheck.Status' = @('Ready', 'Warning', 'Blocked')
    'EndpointForge.ControlCapability.CheckStatus' = @('Available', 'Unavailable')
    'EndpointForge.ControlCapability.FixStatus' = @('NotOffered', 'Unavailable', 'NeedsAdministrator', 'Available')
    'EndpointForge.EndpointComparisonChange.Category' = @(
        'Changed', 'ChecklistChanged', 'CouldNotCheck', 'NewIssue',
        'NowAvailable', 'Improved', 'Unchanged'
    )
    'EndpointForge.ManagementAgentHealth.LocalStatus' = @(
        'LooksReady', 'NeedsAttention', 'NotDetected', 'CouldNotCheck'
    )
    'EndpointForge.ManagementAgentActionResult.Outcome' = @(
        'WhatIf', 'Skipped', 'NotRequired', 'Completed',
        'RequestAccepted', 'PartiallyChanged', 'Failed'
    )
    'EndpointForge.RemediationPlanStep.Action' = @(
        'NoAction', 'NotApplicable', 'Blocked', 'Automatic', 'Manual'
    )
    'EndpointForge.RemediationResult.Outcome' = @(
        'NotRequired', 'NotApplicable', 'EvaluationFailed', 'NotRemediable',
        'WhatIf', 'Skipped', 'Changed', 'VerificationFailed', 'PartiallyChanged', 'Failed'
    )
}
$actualVocabularyNames = @($contract.StatusVocabularies.PSObject.Properties.Name | Sort-Object)
if (($actualVocabularyNames -join "`n") -cne (@($expectedStatusVocabularies.Keys | Sort-Object) -join "`n")) {
    throw 'The public contract status-vocabulary names changed.'
}
foreach ($vocabularyName in $expectedStatusVocabularies.Keys) {
    $actualValues = @($contract.StatusVocabularies.PSObject.Properties[$vocabularyName].Value)
    $expectedValues = @($expectedStatusVocabularies[$vocabularyName])
    if (($actualValues -join "`n") -cne ($expectedValues -join "`n")) {
        throw "The stable status vocabulary '$vocabularyName' changed."
    }
}

Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModulePath -Force -ErrorAction Stop
$commonParameterNames = @(
    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
    'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable',
    'OutVariable', 'OutBuffer', 'PipelineVariable'
)
$commands = @(Get-Command -Module EndpointForge -CommandType Function | Sort-Object Name)
$expectedCommandNames = @($contract.Commands.PSObject.Properties.Name | Sort-Object)
$actualCommandNames = @($commands.Name | Sort-Object)
if (($expectedCommandNames -join "`n") -cne ($actualCommandNames -join "`n")) {
    throw 'The exported command names do not match Data\PublicContract.v1.json.'
}

foreach ($command in $commands) {
    $commandContract = $contract.Commands.PSObject.Properties[$command.Name].Value
    $actualParameters = @(
        $command.Parameters.GetEnumerator() |
            Where-Object Key -NotIn $commonParameterNames |
            Sort-Object Key |
            ForEach-Object { '{0}:{1}' -f $_.Key, $_.Value.ParameterType.FullName }
    )
    $expectedParameters = @($commandContract.Parameters)
    if (($actualParameters -join "`n") -cne ($expectedParameters -join "`n")) {
        throw "The public parameters for '$($command.Name)' do not match the 1.0 contract."
    }

    $actualOutputs = @(
        $command.OutputType |
            ForEach-Object { $_.Name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    $expectedOutputs = @($commandContract.Outputs)
    if (($actualOutputs -join "`n") -cne ($expectedOutputs -join "`n")) {
        throw "The declared output types for '$($command.Name)' do not match the 1.0 contract."
    }

    $publicFile = Join-Path $projectRoot "Public\$($command.Name).ps1"
    $publicSource = Get-Content -LiteralPath $publicFile -Raw
    if ($publicSource -notmatch '(?ms)^\s*\.OUTPUTS\s*\r?\n\s*\S+') {
        throw "Public command '$($command.Name)' must document its output contract in comment-based help."
    }
}

function ConvertFrom-EFQuotedAstText {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    return $Text.Trim().Trim([char[]]@([char]39, [char]34))
}

function Get-EFTextSha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
        )).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

$actualResultSchemas = @{}
$resultSourceFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Public') -Filter '*.ps1' -File
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Private') -Filter '*.ps1' -File
)
foreach ($resultSourceFile in $resultSourceFiles) {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $resultSourceFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if (@($parseErrors).Count -gt 0) {
        throw "Could not parse result source '$($resultSourceFile.FullName)'."
    }
    $hashtables = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.HashtableAst]
    }, $true))
    foreach ($hashtable in $hashtables) {
        $pairs = @($hashtable.KeyValuePairs)
        $typePair = @(
            $pairs | Where-Object {
                (ConvertFrom-EFQuotedAstText -Text $_.Item1.Extent.Text) -ceq 'PSTypeName'
            } | Select-Object -First 1
        )
        if ($typePair.Count -eq 0) { continue }
        $typeName = ConvertFrom-EFQuotedAstText -Text $typePair[0].Item2.Extent.Text
        if ($typeName -notmatch '^EndpointForge\.[A-Za-z0-9]+$') { continue }
        $propertyNames = @(
            $pairs |
                ForEach-Object { ConvertFrom-EFQuotedAstText -Text $_.Item1.Extent.Text } |
                Where-Object { $_ -cne 'PSTypeName' } |
                Sort-Object -Unique
        )
        $schemaText = $propertyNames -join "`n"
        if ($actualResultSchemas.ContainsKey($typeName) -and
            [string]$actualResultSchemas[$typeName] -cne $schemaText) {
            throw "Result type '$typeName' is constructed with inconsistent property sets."
        }
        $actualResultSchemas[$typeName] = $schemaText
    }
}

$expectedResultTypeNames = @($contract.ResultSchemaHashes.PSObject.Properties.Name | Sort-Object)
$actualResultTypeNames = @($actualResultSchemas.Keys | Sort-Object)
if (($expectedResultTypeNames -join "`n") -cne ($actualResultTypeNames -join "`n")) {
    throw 'The EndpointForge result-type set does not match the frozen 1.0 result schemas.'
}
foreach ($resultTypeName in $expectedResultTypeNames) {
    $expectedHash = [string]$contract.ResultSchemaHashes.PSObject.Properties[$resultTypeName].Value
    if ($expectedHash -notmatch '^[A-F0-9]{64}$') {
        throw "Result schema hash for '$resultTypeName' is not a canonical SHA-256 value."
    }
    $actualHash = Get-EFTextSha256 -Text ([string]$actualResultSchemas[$resultTypeName])
    if ($actualHash -cne $expectedHash) {
        throw "The property schema for '$resultTypeName' changed from the frozen 1.0 contract."
    }
}

$schemaPath = Join-Path $projectRoot 'Data\Baseline.schema.json'
$schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
if ([string]$schema.'$id' -ne 'https://raw.githubusercontent.com/swaggysnippets/EndpointForge/v1.0.0/Data/Baseline.schema.json') {
    throw 'The checklist schema must retain the versioned EndpointForge 1.0 identifier.'
}
if ([string]$schema.properties.FormatVersion.const -ne '1.0') {
    throw 'The checklist schema must retain FormatVersion 1.0.'
}

[pscustomobject]@{
    PSTypeName             = 'EndpointForge.PublicContractValidation'
    ContractVersion        = [string]$contract.ContractVersion
    ChecklistFormatVersion = [string]$contract.ChecklistFormatVersion
    CommandCount           = $commands.Count
    StatusVocabularyCount  = $expectedStatusVocabularies.Count
    ResultSchemaCount      = $actualResultSchemas.Count
    IsValid                = $true
}
