BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'EndpointForge HTML reports' {
    It 'converts report content to a self-contained encoded document' {
        $report = [pscustomobject]@{
            ComputerName  = 'PC&01'
            OverallStatus = 'Warning'
            Summary       = '<script>alert("unsafe")</script> & review'
            Findings      = @(
                [pscustomobject]@{
                    Title           = '<script>alert(1)</script>'
                    Severity        = 'High'
                    Status          = 'NonCompliant'
                    Message         = 'A & B'
                    SuggestedAction = 'Review <this> item.'
                }
            )
        }

        $html = InModuleScope EndpointForge -Parameters @{ Report = $report } {
            ConvertTo-EFHtmlReport -InputObject @($Report) -Title 'Check <PC&01>'
        }

        $html | Should -Match '^<!doctype html>'
        $html | Should -Match 'Check &lt;PC&amp;01&gt;'
        $html | Should -Match '&lt;script&gt;alert\(&quot;unsafe&quot;\)&lt;/script&gt; &amp; review'
        $html | Should -Match 'PC&amp;01'
        $html | Should -Match 'A &amp; B'
        $html | Should -Not -Match '(?i)<script(?:\s|>)'
        $html | Should -Not -Match '(?i)(?:src|href)\s*=\s*["'']https?://'
        $html | Should -Not -Match '(?i)@import\s+url'
    }

    It 'renders a blocked readiness result as one plain-language value' {
        $report = [pscustomobject]@{
            PSTypeName      = 'EndpointForge.EndpointReadiness'
            ComputerName    = 'PC-01'
            Status          = 'Blocked'
            AssessmentReady = $false
            Summary         = 'The checklist cannot start.'
        }

        $html = InModuleScope EndpointForge -Parameters @{ Report = $report } {
            ConvertTo-EFHtmlReport -InputObject @($Report)
        }

        $html | Should -Match '>Not available here<'
        $html | Should -Not -Match '\[&quot;Not ready&quot;,&quot;Could not check&quot;\]'
    }

    It 'translates fix receipt outcomes into everyday language' {
        $report = [pscustomobject]@{
            PSTypeName  = 'EndpointForge.RemediationReport'
            ComputerName = 'PC-01'
            Summary     = 'A preview and an error result are shown.'
            Results     = @(
                [pscustomobject]@{ Title = 'Preview item'; Outcome = 'WhatIf'; BeforeValue = 0; AfterValue = 0 },
                [pscustomobject]@{ Title = 'Partial item'; Outcome = 'PartiallyChanged'; BeforeValue = 'Disabled'; AfterValue = 'Manual' },
                [pscustomobject]@{ Title = 'Verify item'; Outcome = 'VerificationFailed'; BeforeValue = 0; AfterValue = 1 }
            )
        }

        $html = InModuleScope EndpointForge -Parameters @{ Report = $report } {
            ConvertTo-EFHtmlReport -InputObject @($Report)
        }

        $html | Should -Match 'Preview only - not changed'
        $html | Should -Match 'A value changed, but the fix did not complete'
        $html | Should -Match 'Changed, but the expected result was not confirmed'
        $html | Should -Not -Match '>WhatIf<|>PartiallyChanged<|>VerificationFailed<'
    }

    It 'infers HTML from the extension and writes UTF-8 without a BOM' {
        $path = Join-Path $TestDrive 'computer-check.html'

        [pscustomobject]@{
            ComputerName  = 'PC-01'
            OverallStatus = 'Healthy'
            Summary       = 'This computer looks good.'
        } | Export-EFEndpointReport -Path $path -Force

        $bytes = [IO.File]::ReadAllBytes($path)
        $text = [IO.File]::ReadAllText($path)
        $text | Should -Match '^<!doctype html>'
        $text | Should -Match 'This computer looks good\.'
        ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
            Should -BeFalse
    }

    It 'appends an HTML extension when the format is explicit' {
        $pathWithoutExtension = Join-Path $TestDrive 'explicit-report'
        $expectedPath = "$pathWithoutExtension.html"

        $created = [pscustomobject]@{ Summary = 'Explicit HTML report.' } |
            Export-EFEndpointReport -Path $pathWithoutExtension -Format Html -Force -PassThru

        $created.FullName | Should -Be $expectedPath
        Test-Path -LiteralPath $expectedPath | Should -BeTrue
        [IO.File]::ReadAllText($expectedPath) | Should -Match 'Explicit HTML report\.'
    }

    It 'requires Force before overwriting an HTML report' {
        $path = Join-Path $TestDrive 'existing.html'
        [IO.File]::WriteAllText($path, 'keep this text')

        {
            [pscustomobject]@{ Summary = 'Replacement.' } |
                Export-EFEndpointReport -Path $path
        } | Should -Throw '*-Force*'
        [IO.File]::ReadAllText($path) | Should -Be 'keep this text'

        [pscustomobject]@{ Summary = 'Replacement.' } |
            Export-EFEndpointReport -Path $path -Force
        [IO.File]::ReadAllText($path) | Should -Match 'Replacement\.'
    }

    It 'honors WhatIf without creating an HTML report or its parent folder' {
        $parent = Join-Path $TestDrive 'not-created'
        $path = Join-Path $parent 'preview.html'

        [pscustomobject]@{ Summary = 'Preview only.' } |
            Export-EFEndpointReport -Path $path -WhatIf

        Test-Path -LiteralPath $path | Should -BeFalse
        Test-Path -LiteralPath $parent | Should -BeFalse
    }

    It 'rejects an explicit format that does not match the path extension' {
        $path = Join-Path $TestDrive 'wrong.json'

        {
            [pscustomobject]@{ Summary = 'Wrong extension.' } |
                Export-EFEndpointReport -Path $path -Format Html -Force
        } | Should -Throw '*does not match*'
    }

    It 'keeps AsArray limited to JSON output' {
        $path = Join-Path $TestDrive 'array.html'

        {
            [pscustomobject]@{ Summary = 'One item.' } |
                Export-EFEndpointReport -Path $path -AsArray -Force
        } | Should -Throw '*only for JSON*'
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'keeps null input limited to JSON output' {
        $path = Join-Path $TestDrive 'null.html'

        {
            Export-EFEndpointReport -InputObject $null -Path $path -Format Html -Force
        } | Should -Throw '*only for JSON*'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}
