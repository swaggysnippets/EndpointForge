BeforeAll {
    $script:StagedPackageProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:StagedPackageVerifier = Join-Path $script:StagedPackageProjectRoot 'build\Test-StagedModule.ps1'
    $script:PesterRunner = Join-Path $script:StagedPackageProjectRoot 'build\Invoke-PesterTests.ps1'

    function Get-EFStagedPackageFixture {
        param(
            [Parameter(Mandatory)]
            [string]$Root
        )

        $modulePath = Join-Path $Root 'EndpointForge'
        $markerPath = Join-Path $Root 'staged-code-executed.txt'
        $null = New-Item -ItemType Directory -Path $modulePath -Force
        $escapedMarkerPath = $markerPath.Replace("'", "''")
        $manifestContent = @"
@{
    RootModule = 'EndpointForge.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c49dcad4-e3ab-49ee-87a5-dd24936f63b8'
    FunctionsToExport = @()
}
"@
        $moduleContent = "[IO.File]::WriteAllText('$escapedMarkerPath', 'executed')"
        [IO.File]::WriteAllText(
            (Join-Path $modulePath 'EndpointForge.psd1'),
            $manifestContent,
            [Text.UTF8Encoding]::new($false)
        )
        [IO.File]::WriteAllText(
            (Join-Path $modulePath 'EndpointForge.psm1'),
            $moduleContent,
            [Text.UTF8Encoding]::new($false)
        )

        [pscustomobject]@{
            Root = $Root
            ModulePath = $modulePath
            InventoryPath = Join-Path $Root 'EndpointForge.sha256.json'
            MarkerPath = $markerPath
        }
    }

    function Get-EFStagedPackageHashRecord {
        param(
            [Parameter(Mandatory)]
            [string]$ModulePath
        )

        @(
            Get-ChildItem -LiteralPath $ModulePath -Recurse -Force -File |
                Get-FileHash -Algorithm SHA256 |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        Path = $_.Path.Substring($ModulePath.Length + 1)
                        Algorithm = 'SHA256'
                        Hash = $_.Hash
                    }
                }
        )
    }

    function Write-EFStagedPackageInventory {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [object[]]$Records
        )

        $json = ConvertTo-Json -InputObject @($Records) -Depth 4
        [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
    }
}

Describe 'Pester runner failure boundary' {
    It 'treats discovery and container failures as failed runs' {
        $runnerSource = Get-Content -LiteralPath $script:PesterRunner -Raw

        $runnerSource | Should -Match 'FailedContainersCount'
        $runnerSource | Should -Match 'FailedBlocksCount'
        $runnerSource | Should -Match '\$result\.Result\s+-ne\s+''Passed'''
        $runnerSource | Should -Match 'discovered no tests'
    }
}

Describe 'Staged package verification order and completeness' {
    BeforeEach {
        $script:StagedPackageTestRoot = Join-Path (
            [IO.Path]::GetTempPath()
        ) ("EndpointForge-StagedTest-{0}" -f [guid]::NewGuid())
        $script:StagedPackageFixture = Get-EFStagedPackageFixture -Root $script:StagedPackageTestRoot
    }

    AfterEach {
        Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $script:StagedPackageTestRoot -PathType Container) {
            $resolvedTestRoot = [IO.Path]::GetFullPath($script:StagedPackageTestRoot)
            $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase) -and
                [IO.Path]::GetFileName($resolvedTestRoot).StartsWith(
                    'EndpointForge-StagedTest-',
                    [StringComparison]::Ordinal
                )) {
                Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
            }
        }
        Remove-Variable StagedPackageTestRoot -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable StagedPackageFixture -Scope Script -ErrorAction SilentlyContinue
    }

    It 'rejects a non-array inventory before importing staged PowerShell' {
        [IO.File]::WriteAllText(
            $script:StagedPackageFixture.InventoryPath,
            '{}',
            [Text.UTF8Encoding]::new($false)
        )

        {
            & $script:StagedPackageVerifier -ModulePath $script:StagedPackageFixture.ModulePath `
                -HashInventoryPath $script:StagedPackageFixture.InventoryPath
        } | Should -Throw '*non-empty JSON array*'
        Test-Path -LiteralPath $script:StagedPackageFixture.MarkerPath | Should -BeFalse
    }

    It 'requires the exact inventory object shape before importing staged PowerShell' {
        $records = @(Get-EFStagedPackageHashRecord -ModulePath $script:StagedPackageFixture.ModulePath)
        $records[0] | Add-Member -NotePropertyName Unexpected -NotePropertyValue $true
        Write-EFStagedPackageInventory -Path $script:StagedPackageFixture.InventoryPath -Records $records

        {
            & $script:StagedPackageVerifier -ModulePath $script:StagedPackageFixture.ModulePath `
                -HashInventoryPath $script:StagedPackageFixture.InventoryPath
        } | Should -Throw '*exactly Path, Algorithm, and Hash*'
        Test-Path -LiteralPath $script:StagedPackageFixture.MarkerPath | Should -BeFalse
    }

    It 'rejects an incomplete file set before importing staged PowerShell' {
        $records = @(Get-EFStagedPackageHashRecord -ModulePath $script:StagedPackageFixture.ModulePath)
        [IO.File]::WriteAllText(
            (Join-Path $script:StagedPackageFixture.ModulePath 'unlisted.txt'),
            'unlisted',
            [Text.UTF8Encoding]::new($false)
        )
        Write-EFStagedPackageInventory -Path $script:StagedPackageFixture.InventoryPath -Records $records

        {
            & $script:StagedPackageVerifier -ModulePath $script:StagedPackageFixture.ModulePath `
                -HashInventoryPath $script:StagedPackageFixture.InventoryPath
        } | Should -Throw '*does not match the hash inventory*'
        Test-Path -LiteralPath $script:StagedPackageFixture.MarkerPath | Should -BeFalse
    }

    It 'verifies every hash before importing staged PowerShell' {
        $records = @(Get-EFStagedPackageHashRecord -ModulePath $script:StagedPackageFixture.ModulePath)
        @($records | Where-Object Path -eq 'EndpointForge.psm1')[0].Hash = ('0' * 64) -join ''
        Write-EFStagedPackageInventory -Path $script:StagedPackageFixture.InventoryPath -Records $records

        {
            & $script:StagedPackageVerifier -ModulePath $script:StagedPackageFixture.ModulePath `
                -HashInventoryPath $script:StagedPackageFixture.InventoryPath
        } | Should -Throw "*SHA-256 verification failed for 'EndpointForge.psm1'*"
        Test-Path -LiteralPath $script:StagedPackageFixture.MarkerPath | Should -BeFalse
    }
}
