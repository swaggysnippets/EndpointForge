# EndpointForge

EndpointForge is an enterprise-oriented PowerShell toolkit for Windows endpoint inventory, health checks, policy compliance, guarded remediation, and structured reporting. It is designed for local execution through Intune, Configuration Manager, RMM platforms, scheduled tasks, or PowerShell remoting.

The module favors predictable automation over hidden behavior:

- read-only collection commands do not require elevation;
- state-changing commands support `-WhatIf` and `-Confirm`;
- remediation is limited to declared, validated control types;
- every compliance and health report includes a deterministic `ExitCode` property;
- logs are newline-delimited JSON for ingestion by enterprise tooling;
- unsupported Windows features report `NotApplicable` instead of ending the full run;
- installed software is read from uninstall registry keys—`Win32_Product` is never queried.

## Start here: your first endpoint check in 60 seconds

Run one installation command in a normal PowerShell window. `CurrentUser` avoids an
administrator prompt and is sufficient for read-only checks:

```powershell
# PowerShell 7+ with Microsoft.PowerShell.PSResourceGet
Install-PSResource -Name EndpointForge -Scope CurrentUser

# OR Windows PowerShell 5.1 with PowerShellGet
Install-Module -Name EndpointForge -Scope CurrentUser
```

Import the module and open the guided operator menu:

```powershell
Import-Module EndpointForge
Show-EFMenu
```

The menu puts the safe path first: assess, review findings, build a plan, preview selected
controls, and only then offer a guarded apply action. Assessment, findings, planning, and
preview are read-only. Apply requires Administrator access, a fresh `WhatIf` preview,
specific control selection, and typing `APPLY` exactly. EndpointForge never restarts the
device.

Prefer direct commands in scripts and unattended management systems:

```powershell
$summary = Get-EFEndpointSummary -NoProgress
$summary | Show-EFEndpointSummary
```

`Get-EFEndpointSummary` returns a normal PowerShell object for pipelines and automation.
`Show-EFEndpointSummary` is the human-readable terminal view; add `-Detailed` for control
details, `-NoColor` for plain-text logs, or `-PassThru` to keep the summary in the pipeline.
`Show-EFMenu` is an interactive facade and should not be used in unattended jobs.

## Guided console menu

```powershell
# Use a custom baseline and include installed software in menu assessments
Show-EFMenu -Baseline .\Contoso.Workstation.json -IncludeSoftware

# Plain output, quiet progress, and a session object after quitting
$menuSession = Show-EFMenu -NoColor -NoProgress -PassThru
```

The linear menu works in Windows PowerShell 5.1, PowerShell 7, Windows Terminal, VS Code,
Server Core, and PowerShell remoting. It uses numbered `Read-Host` prompts instead of
arrow keys, cursor control, WPF, or `Out-GridView`. `-NoPause` removes only the
Press Enter pauses between actions; it never skips control selection or the `APPLY`
safety acknowledgement. Set the standard `NO_COLOR` environment variable or use
`-NoColor` for color-free output.

By default, menu export writes a timestamped JSON session report beneath
`Documents\EndpointForge Reports`. The directory is not created until export is chosen.
Use `-ReportDirectory` to select an enterprise-approved location.

## Requirements

- Windows 10, Windows 11, or Windows Server 2016 and later
- Windows PowerShell 5.1 or PowerShell 7+
- An elevated session for remediation and for complete BitLocker, TPM, Secure Boot, and optional-feature posture data

Most inventory and health data is available to standard users. Windows protects some read-only security APIs behind administrator privileges; those capabilities are returned as collection notes or evaluation errors rather than silently omitted. The module imports on non-Windows systems for packaging and command discovery, but endpoint commands require Windows.

## Installation and verification

For a shared machine-wide installation, open PowerShell as Administrator and use
`-Scope AllUsers`. For normal interactive use, prefer `-Scope CurrentUser` as shown
above. Verify the installation before the first run:

```powershell
Get-Module -ListAvailable EndpointForge | Select-Object Name, Version, ModuleBase
Import-Module EndpointForge
Get-Command -Module EndpointForge
```

For local development, clone the repository and import the manifest:

```powershell
Import-Module .\EndpointForge.psd1 -Force
```

## Object-first quick start

```powershell
# One structured result for operators and automation
$summary = Get-EFEndpointSummary -MinimumFreeSpacePercent 15 -MaximumUptimeDays 30
$summary | Show-EFEndpointSummary -Detailed
$summary | Export-EFEndpointReport -Path C:\ProgramData\EndpointForge\summary.json -Force

# Focused collection commands remain available
$inventory = Get-EFEndpointInventory
$health = Get-EFEndpointHealth
$compliance = Get-EFComplianceReport
$compliance.Results | Where-Object Status -ne 'Compliant'

# Plan and preview before rollout; neither command changes state
$plan = Get-EFRemediationPlan
$plan
Invoke-EFEndpointRemediation -WhatIf

# Apply supported changes from an elevated session and keep confirmation enabled
$remediation = Invoke-EFEndpointRemediation

# Verify independently after the change (Boolean, suitable for if statements)
Test-EFEndpointCompliance
```

## Commands

| Command | Purpose | Changes endpoint state |
|---|---|---:|
| `Show-EFMenu` | Guided interactive assessment, planning, preview, guarded apply, baseline, and export workflow | Only when the operator explicitly completes Apply; can also write reports or baselines |
| `Get-EFEndpointSummary` | Combines identity, health, reboot, compliance, and collection quality into one automation-friendly result | No |
| `Show-EFEndpointSummary` | Renders a concise or detailed operator view; supports plain text with `-NoColor` | No |
| `Get-EFEndpointInventory` | Hardware, OS, disk, network, security, and optional software inventory | No |
| `Get-EFInstalledSoftware` | Registry-based machine and user software inventory | No |
| `Get-EFPendingReboot` | Servicing, update, rename, and file-operation restart indicators | No |
| `Get-EFEndpointHealth` | Monitoring-friendly operational health with thresholds and exit code | No |
| `Get-EFBaseline` | Lists or loads validated compliance baselines | No |
| `New-EFBaseline` | Creates a starter, recommended, or audit-only baseline JSON file | Writes a baseline file |
| `Test-EFBaseline` | Validates a built-in, file-based, or in-memory baseline before use | No |
| `Test-EFEndpointCompliance` | Returns a Boolean compliance answer; use `-PassThru` for the report | No |
| `Get-EFComplianceReport` | Returns the full compliance report, control results, score, and exit code | No |
| `Get-EFRemediationPlan` | Explains applicable changes, elevation, and reboot impact before execution | No |
| `Invoke-EFEndpointRemediation` | Applies supported controls with elevation and ShouldProcess guards | Yes |
| `Export-EFEndpointReport` | Writes JSON, CSV, or CLIXML reports | Writes a report file |
| `Get-EFConfiguration` | Reads current logging and retry configuration | No |
| `Set-EFConfiguration` | Changes in-memory module configuration | Session only |

All commands include comment-based help:

```powershell
Get-Help Invoke-EFEndpointRemediation -Full
Get-Help about_EndpointForge
```

## Recommended operator workflow

Use the same progression for an interactive repair, a pilot ring, or an automation
wrapper: **observe → validate → plan → preview → apply → verify → export**.

Interactive operators can run that entire progression with `Show-EFMenu`. The direct
commands below are the equivalent object-first workflow for scripts, scheduled tasks,
Intune, RMM tools, and other unattended hosts.

### 1. Observe the endpoint

```powershell
$summary = Get-EFEndpointSummary -NoProgress
$summary | Show-EFEndpointSummary -Detailed
```

Omit `-NoProgress` at an interactive terminal. Use it in Intune, scheduled tasks, CI,
or any host where progress records would add noise.

### 2. Select and validate the baseline

```powershell
$baseline = Get-EFBaseline -Name EnterpriseRecommended
$baseline | Test-EFBaseline
```

Validation checks the baseline contract; it does not evaluate or change the endpoint.

### 3. Review the change plan

```powershell
$plan = Get-EFRemediationPlan -Baseline $baseline -IncludeCompliant -NoProgress
$plan
```

The plan identifies compliant, noncompliant, non-remediable, and unavailable controls,
and calls out elevation and restart requirements before any change is attempted. Omit
`-IncludeCompliant` for a shorter action-focused plan. Use `-ControlId` to scope both the
plan and the later remediation to approved controls.

### 4. Preview, apply, and verify

```powershell
$approved = 'EF-FW-DOMAIN', 'EF-UAC-ENABLED'

Invoke-EFEndpointRemediation -Baseline $baseline -ControlId $approved -WhatIf
$result = Invoke-EFEndpointRemediation -Baseline $baseline -ControlId $approved
$verification = Get-EFComplianceReport -Baseline $baseline -ControlId $approved
```

Run the apply step in an elevated PowerShell session. Leave confirmation enabled for
interactive work. In centrally approved, non-interactive automation, use
`-Confirm:$false` only after validating the plan and `-WhatIf` output in a representative
pilot ring.

### 5. Export evidence

```powershell
$result | Export-EFEndpointReport `
    -Path C:\ProgramData\EndpointForge\Reports\remediation.json `
    -Force

$verification | Export-EFEndpointReport `
    -Path C:\ProgramData\EndpointForge\Reports\verification.json `
    -Force
```

The object returned by an EndpointForge command is the automation contract. The output
from `Show-EFEndpointSummary` is for people and must not be parsed by scripts.

## Built-in baseline

`EnterpriseRecommended` contains ten intentionally conservative controls:

- Domain, Private, and Public Windows Firewall profiles enabled
- User Account Control enabled
- Microsoft Defender real-time protection enabled when Defender is available
- SMB 1.0 optional feature disabled when present
- Windows Update service not disabled
- BitLocker protection audited on the operating-system drive
- Secure Boot audited on supported UEFI systems
- TPM presence and readiness audited

BitLocker, Secure Boot, and TPM controls are audit-only. EndpointForge does not automatically enable encryption, change firmware settings, clear a TPM, reboot a device, install software, or download and execute remote content.

### Custom baselines

Create a valid starting file instead of hand-writing the full contract. `Starter` creates a
small editable example, `EnterpriseRecommended` copies the built-in baseline, and
`AuditOnly` creates a non-remediating starting point:

```powershell
New-EFBaseline `
    -Name 'Contoso.Workstation' `
    -Description 'Contoso workstation security policy' `
    -Template Starter `
    -Path .\Contoso.Workstation.json

Test-EFBaseline -Path .\Contoso.Workstation.json
$baseline = Get-EFBaseline -Path .\Contoso.Workstation.json
Get-EFRemediationPlan -Baseline $baseline
```

`New-EFBaseline` supports `-WhatIf` and will not replace an existing file unless `-Force`
is specified. Validate after every edit and before every deployment. `Test-EFBaseline`
also accepts a built-in name or an in-memory object through the pipeline.

For a complete example, see
[`examples/Contoso.Workstation.json`](examples/Contoso.Workstation.json). Editor tooling
can use the included [`Data/Baseline.schema.json`](Data/Baseline.schema.json) for inline
completion and validation.

Supported control types are:

| Type | Evaluated | Remediated |
|---|---:|---:|
| `Registry` | Yes | Yes |
| `Service` | Yes | Yes |
| `FirewallProfile` | Yes | Yes |
| `Defender` | Yes | Real-time protection only |
| `WindowsOptionalFeature` | Yes | Yes, without automatic restart |
| `BitLocker` | Yes | No |
| `SecureBoot` | Yes | No |
| `Tpm` | Yes | No |

A custom control must explicitly set `Remediable`. Baselines are rejected when they have missing names, versions, controls, duplicate control IDs, or unsupported types.

## Automation contracts

EndpointForge functions do not call `exit` from inside the module.
`Test-EFEndpointCompliance` returns `$true` or `$false`, which makes it safe to use directly
in an `if` statement. Use `Get-EFComplianceReport` (or
`Test-EFEndpointCompliance -PassThru`) when an orchestrator needs control details, score,
or `ExitCode`.

### Compliance exit codes

| Code | Meaning |
|---:|---|
| 0 | All applicable controls are compliant |
| 2 | One or more controls are noncompliant |
| 3 | One or more controls could not be evaluated |

### Health exit codes

| Code | Meaning |
|---:|---|
| 0 | Healthy |
| 1 | Warning |
| 2 | Critical |

For an Intune proactive remediation pair, see [`examples/Intune`](examples/Intune). For a scheduled maintenance pattern, see [`examples/Invoke-EndpointMaintenance.ps1`](examples/Invoke-EndpointMaintenance.ps1). For read-only fleet collection over PowerShell remoting, see [`examples/Invoke-RemoteAssessment.ps1`](examples/Invoke-RemoteAssessment.ps1).

## Structured logging

File logging is off by default. Enable it for the current process:

```powershell
Set-EFConfiguration `
    -LogPath '%ProgramData%\EndpointForge\endpointforge.jsonl' `
    -LogLevel Information
```

Each line is an independent JSON document with UTC time, level, computer, process, correlation ID, message, and command-specific data. EndpointForge does not intentionally log uninstall strings, serial numbers, interactive usernames, or baseline registry contents. Report data is separate and exported only when requested.

Reports can still contain host identity, hardware, network, software, security posture, and
remediation evidence. Store reports, logs, and custom baselines in enterprise-approved
locations with least-privilege ACLs and appropriate retention. For centrally managed runs,
limit write access to the management identity, `SYSTEM`, and authorized administrators;
verify inherited permissions with `Get-Acl`. See [`SECURITY.md`](SECURITY.md) for the full
data-handling and privileged-import guidance.

## Troubleshooting first-run and capability messages

EndpointForge distinguishes an endpoint that is out of policy from one it could not fully
inspect:

| Result | Meaning | Operator action |
|---|---|---|
| `NonCompliant` | The current value was read and does not match the baseline | Review `Get-EFRemediationPlan`, preview with `-WhatIf`, then remediate if approved |
| `NotApplicable` | The feature, service, or Windows capability is absent or unsupported | Usually no action; confirm the baseline is appropriate for that device class |
| `Error` | EndpointForge could not establish the current value | Read the result message, check elevation and platform capability, then rerun |

### “Requires elevation”, “Access denied”, or “Unable to set proper privileges”

Most summary, inventory, health, and compliance data works as a standard user. Windows
may still restrict read-only BitLocker, TPM, Secure Boot, and optional-feature providers.
Remediation always requires elevation when a change is needed.

1. Keep the standard-user result as evidence; collection errors are exposed, not hidden.
2. Open Windows Terminal or PowerShell with **Run as administrator**.
3. Rerun `Get-EFEndpointSummary | Show-EFEndpointSummary -Detailed`.
4. If access is still denied, check MDM, Group Policy, Defender tamper protection, and
   application-control policy. Those controls can intentionally block local inspection or
   changes.

Do not treat `Error` as compliant, and do not suppress it merely to obtain a green score.
In automation, retain the report and use its `ExitCode`.

### Secure Boot, TPM, BitLocker, Defender, or optional-feature data is unavailable

First rerun elevated. If the result remains `NotApplicable`, the provider or capability may
not exist on that Windows edition, Server role, virtual machine, firmware mode, or hardware
model. If it remains `Error`, inspect the detailed control message:

```powershell
$summary = Get-EFEndpointSummary -NoProgress
$summary | Show-EFEndpointSummary -Detailed -NoColor

$compliance = Get-EFComplianceReport
$compliance.Results |
    Where-Object Status -in 'Error', 'NotApplicable' |
    Format-Table ControlId, Status, Message -Wrap
```

Use device-class-specific baselines when a capability is intentionally absent. Audit-only
controls report posture but are never enabled automatically.

### The module installs but does not import

Confirm which copy PowerShell discovered and review effective execution policy:

```powershell
Get-Module -ListAvailable EndpointForge | Select-Object Name, Version, ModuleBase
Get-ExecutionPolicy -List
Import-Module EndpointForge -Verbose
```

If the error says scripts or format data are blocked, follow your organization's
application-control and execution-policy process. Where organizational policy permits,
`RemoteSigned` at `CurrentUser` scope is generally sufficient for locally created scripts;
do not bypass a centrally managed policy. Reinstalling the module will not override Group
Policy.

### A remediation was attempted but verification failed

The toolkit verifies a control after changing it and reports `VerificationFailed` rather
than claiming success. Review the result message and correlation ID, then check for policy
refresh, Defender tamper protection, a service that rejects the requested state, or a
required restart:

```powershell
$result.Results |
    Where-Object Outcome -in 'Failed', 'EvaluationFailed', 'VerificationFailed' |
    Format-Table ControlId, Outcome, Message -Wrap

$result.RebootRequired
Get-EFPendingReboot
```

After resolving the owner policy or completing an approved restart, run
`Get-EFComplianceReport` again. EndpointForge never restarts a device automatically.

### A custom baseline is rejected

Validate the exact artifact before evaluating the endpoint:

```powershell
Test-EFBaseline -Path .\Contoso.Workstation.json
Get-EFBaseline -Path .\Contoso.Workstation.json
```

Typical causes are malformed JSON, duplicate control IDs, a missing name or semantic
version, an unsupported control type, or type-specific fields that do not match the JSON
Schema. Start again with `New-EFBaseline` when comparing against a known-good template is
faster than repairing the file.

## Release and Gallery publication

Install the development-only quality tools, then run the source checks and tests in both
Windows PowerShell 5.1 and PowerShell 7. The commands below show one host; repeat them in
the other host or require a successful run of both jobs in `.github/workflows/ci.yml`:

```powershell
$toolRoot = Join-Path $PWD '.build\dependencies'
Save-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Path $toolRoot
Save-Module Pester -RequiredVersion 5.7.1 -Path $toolRoot
$env:PSModulePath = "$toolRoot;$env:PSModulePath"

.\build\Test-Module.ps1 -RequireScriptAnalyzer
.\build\Invoke-PesterTests.ps1
.\build\Test-WindowsRuntime.ps1
```

The manifest identifies Logan Bamborough as the publisher and links to the public
[EndpointForge repository](https://github.com/swaggysnippets/EndpointForge). GitHub private
vulnerability reporting is enabled. Before Gallery publication, configure `PSGALLERY_API_KEY`
as a secret in the protected `powershell-gallery` GitHub environment. Never commit, print, or
place the Gallery key in a script or release artifact.

Build once from the reviewed source and verify that exact staged package and SHA-256
inventory. Do not edit `artifacts/EndpointForge` after this step; rebuild it instead:

```powershell
.\build\Build-Module.ps1 -SkipTests
$staged = .\build\Test-StagedModule.ps1
$readiness = .\build\Test-PublishReadiness.ps1
$staged | Format-List
$readiness | Format-List

$manifest = Test-ModuleManifest .\artifacts\EndpointForge\EndpointForge.psd1
$expectedVersion = [version](Read-Host 'Expected release version')
if ($manifest.Version -ne $expectedVersion) {
    throw "Review the release version before publishing: $($manifest.Version)"
}
if (-not $staged.HashesVerified) {
    throw 'The staged package hash inventory was not verified.'
}
if (-not $readiness.IsReady) {
    throw 'The staged package did not pass publish-readiness validation.'
}
```

For an enterprise Authenticode release, sign the staged PowerShell files with an approved
code-signing certificate and timestamp service, then require signatures in the final gate:

```powershell
.\build\Protect-StagedModule.ps1 `
    -CertificateThumbprint '<approved code-signing certificate thumbprint>' `
    -TimestampServer '<approved timestamp service URL>'

.\build\Test-StagedModule.ps1
.\build\Test-PublishReadiness.ps1 -RequireSignature
```

The signing command regenerates the external SHA-256 inventory. Do not rebuild after
signing, because a rebuild intentionally replaces the staged directory from reviewed
source.

Enter the intended release version at the prompt. Review the staged `README.md`,
`SECURITY.md`, `CONTRIBUTING.md`, manifest, release notes, and changelog; confirm the release
tag will be exactly `v<manifest version>`. The preferred publication path is a GitHub release
after required CI checks pass. `.github/workflows/publish.yml` validates the tag and
publishes the newly built package using the protected environment secret.

For an authorized manual fallback, use a current PowerShellGet installation and provide the
API key through the process environment only after all preflight checks pass:

```powershell
if ([string]::IsNullOrWhiteSpace($env:PSGALLERY_API_KEY)) {
    throw 'PSGALLERY_API_KEY is not configured in this process.'
}

Publish-Module `
    -Path .\artifacts\EndpointForge `
    -Repository PSGallery `
    -NuGetApiKey $env:PSGALLERY_API_KEY `
    -Verbose

Remove-Item Env:\PSGALLERY_API_KEY -ErrorAction SilentlyContinue
```

After publication, install the released version into a clean session from PSGallery, import
it, run `Get-Command -Module EndpointForge`, and verify a read-only assessment before
announcing the release. PowerShell Gallery versions are immutable; publish a new version to
correct a released package.

## Security

See [`SECURITY.md`](SECURITY.md). Test custom baselines in a representative ring, use `-WhatIf`, deploy read-only evaluation first, and approve remediating controls explicitly. Group Policy, MDM, or Defender tamper protection can intentionally override local changes; EndpointForge reports verification failure rather than claiming success.

## License

MIT. See [`LICENSE`](LICENSE).
