# EndpointForge

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/EndpointForge?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/EndpointForge)
[![CI](https://github.com/swaggysnippets/EndpointForge/actions/workflows/ci.yml/badge.svg)](https://github.com/swaggysnippets/EndpointForge/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

EndpointForge helps you check and maintain Windows computers without requiring you to
understand configuration frameworks. It answers four practical questions:

- Does this computer look healthy?
- Do important Windows settings match the selected checklist?
- Which problems can EndpointForge safely preview and fix?
- What changed between an earlier check and a later one?

The guided menu uses everyday language, clearly labels every choice that can change a
setting, and works in Windows PowerShell 5.1 or PowerShell 7 on Windows.

## Start here

Install the current release from the PowerShell Gallery:

```powershell
Install-Module EndpointForge -Scope CurrentUser
```

Open the guided menu:

```powershell
Show-EFMenu
```

The first screen is organized around what you want to accomplish:

```text
EndpointForge - Windows computer helper
Checks health and security, explains problems, and safely previews supported fixes.

1. Check this computer now              [does not change Windows]
2. Understand the latest results        [does not change Windows]
3. Fix selected problems safely         [can change settings after approval]
4. Save reports or compare checks       [creates files only when you choose Save]
5. Check other computers                [read-only; advanced setup required]
6. Change what EndpointForge checks     [does not change Windows]
A. Tools for IT scripts and troubleshooting
H. Help - explain every choice
Q. Exit EndpointForge
```

You can run normal checks as a standard user. Some protected details and all approved
fixes require a PowerShell window opened with **Run as administrator**.

## What EndpointForge can do

- Run one read-only computer check that combines health, restart status, security
  information, and a Windows settings checklist.
- Explain results as **Looks good**, **Needs attention**, **Urgent attention**, or
  **Could not check everything**.
- Explain why each built-in checklist item matters, how it is checked, what a supported
  fix would change, restart impact, and recovery guidance.
- Preview supported fixes without changing Windows.
- Apply only the items you explicitly select, after a fresh preview and an exact `APPLY`
  confirmation in an Administrator window.
- Record before and after values for approved changes.
- Save a self-contained HTML report for people or JSON, CSV, and CLIXML for scripts.
- Compare two checks without claiming an incomplete later result was fixed.
- Check several already-managed computers through PowerShell remoting without changing
  them.
- Validate and create organization-specific checklist JSON files.

## Safety boundaries

EndpointForge intentionally does **not**:

- restart Windows;
- install updates;
- turn on BitLocker or start drive encryption;
- change Secure Boot, firmware, or Trusted Platform Module settings;
- install itself on another computer or enable PowerShell remoting;
- bypass Group Policy, mobile-device management, Defender tamper protection, or another
  security product;
- in the guided menu, make an automatic change without item selection, a fresh preview,
  Administrator permission, and the exact `APPLY` acknowledgement;
- promise automatic rollback.

The module records before and after values, but a universal rollback would be unsafe.
Organization policy, later Windows changes, service dependencies, firewall rules, and
other management tools can all affect the setting after EndpointForge runs. Use the
receipt and its recovery guidance with your approved change process.

## Everyday glossary

| Term | Plain-language meaning |
|---|---|
| Computer checkup | A read-only look at health and important Windows settings. |
| Checklist | A list of Windows settings and their expected values. Selecting one does not apply it. |
| Baseline | The script-facing name for a checklist. Existing commands keep this name for compatibility. |
| Checklist item | One setting in a checklist. Script output calls it a control. |
| Matches | The current value could be read and equals the checklist value. Script output calls this compliant. |
| Does not match | The current value was read and differs from the checklist. Script output calls this noncompliant. |
| Could not check | Windows did not provide a definite answer. This is not treated as passing or fixed. |
| Preview | A no-change rehearsal that shows the selected supported fixes. PowerShell calls this `WhatIf`. |
| Supported fix | A narrow setting change EndpointForge knows how to preview and verify. Script output calls it automatic remediation. |
| Manual review | EndpointForge explains the issue but deliberately does not change it. |
| Administrator | A PowerShell window opened with **Run as administrator**. This is also called an elevated session. |
| Endpoint | An IT term for a managed computer. |

You do not need to know DSC, compliance systems, or PowerShell object models to use the
menu.

## Run a check without the menu

The recommended read-only command is:

```powershell
$check = Get-EFEndpointSummary -NoProgress
$check | Show-EFEndpointSummary
```

For a complete explanation of every item:

```powershell
$check | Show-EFEndpointSummary -Detailed
```

The command returns structured data for scripts. The display is for people; do not parse
the display text in automation.

Before a check, you can ask what the current PowerShell window is capable of doing:

```powershell
Get-EFEndpointReadiness
```

Readiness checks the platform, checklist, Administrator permission, remote-session
context, and required Windows commands. It does not evaluate the settings themselves and
does not change anything.

## Understand results

The overall result separates a known problem from missing evidence:

| Display | Meaning | Script value |
|---|---|---|
| Looks good | Checked health and settings do not need attention. | `Healthy` / `Compliant` |
| Needs attention | A warning or checklist difference was found. | `Warning` / `NonCompliant` |
| Urgent attention | A critical health or security difference was found. | `Critical` |
| Could not check everything | One or more answers were unavailable or protected. | `Incomplete`, `Unknown`, or `Error` |
| Not used on this computer | The Windows feature is not present or applicable. | `NotApplicable` |

Unknown information is never silently counted as healthy. A later incomplete result is
also never described as an improvement.

## Preview and apply supported fixes

The safest experience is menu option 3. The guided sequence is fixed:

1. Run or reuse a read-only computer check.
2. Explain every item needing attention.
3. Select only supported fixes.
4. Run a mandatory preview that cannot change Windows.
5. Stop if the preview is incomplete.
6. Require an Administrator window.
7. Show the computer, selected items, current values, expected values, and restart impact.
8. Require `APPLY` exactly.
9. Apply the selected items and immediately check their new values.
10. Run a fresh computer check and show the before-and-after comparison.

A standard-user window can complete the preview. It will then explain how to reopen
PowerShell as Administrator; it does not try to restart or elevate itself.

The equivalent script workflow is:

```powershell
$plan = Get-EFRemediationPlan -NoProgress
$plan.Steps | Where-Object CanFixAutomatically

# No-change preview
Invoke-EFEndpointRemediation -ControlId 'EF-FW-DOMAIN' -WhatIf -NoProgress

# Apply only after independent approval, from an Administrator window
Invoke-EFEndpointRemediation -ControlId 'EF-FW-DOMAIN' -Confirm:$false -NoProgress
```

The low-level apply command supports normal PowerShell `ShouldProcess` behavior. In your
own automation, you are responsible for approval, selection, and change control. The menu
adds the extra exact-text acknowledgement.

### Built-in supported fixes

The built-in `EnterpriseRecommended` checklist can preview narrow changes for:

- Domain, Private, and Public Windows Firewall profiles;
- User Account Control;
- Microsoft Defender real-time protection when Defender manages it;
- the SMB 1.0 Windows optional feature;
- the Windows Update service start setting.

BitLocker, Secure Boot, and TPM readiness are report-only. EndpointForge will not change
them automatically.

## Save reports

HTML is recommended when a person will read the result:

```powershell
Get-EFEndpointSummary -NoProgress |
    Export-EFEndpointReport -Path .\computer-check.html
```

The HTML file is self-contained, uses embedded styling, loads no JavaScript, fonts, or
internet content, and HTML-encodes report values. It is UTF-8 without a byte-order mark.

JSON preserves nested data for scripts and support tools:

```powershell
Get-EFEndpointSummary -NoProgress |
    Export-EFEndpointReport -Path .\computer-check.json
```

CSV and CLIXML are also supported:

```powershell
Get-EFInstalledSoftware |
    Export-EFEndpointReport -Path .\software.csv

Get-EFEndpointSummary -NoProgress |
    Export-EFEndpointReport -Path .\computer-check.clixml
```

The extension selects the format. You may also use `-Format Html`, `Json`, `Csv`, or
`Clixml`. Existing files require `-Force`, and export supports `-WhatIf`.

Reports can contain computer names, hardware, installed software, security posture, and
change evidence. Store them only in an approved location.

## Compare two checks

Compare two saved JSON reports:

```powershell
$difference = Compare-EFEndpointSummary -Before .\before.json -After .\after.json
$difference
```

Or compare objects directly:

```powershell
$before = Get-EFEndpointSummary -NoProgress
# An approved change or other maintenance occurs here.
$after = Get-EFEndpointSummary -NoProgress
Compare-EFEndpointSummary $before $after
```

The comparison reports improved items, new issues, unchanged items, information that is
now available, and items that could not be checked. By default, it rejects checks from
different computer names. It also warns when the checklist name or version changed, since
that is not a like-for-like progress check.

## Check several computers without changing them

`Get-EFFleetSummary` is strictly read-only:

```powershell
$fleet = Get-EFFleetSummary -ComputerName PC-101,PC-102
$fleet.Results
$fleet.Failures
```

Before this works, each target computer must already:

- allow PowerShell remoting under your organization's policy;
- have EndpointForge 0.4.0 or later installed;
- allow the connecting account to run the check.

EndpointForge does not install the module remotely, enable WinRM, change TrustedHosts, or
run fixes. Connection failures are returned alongside successful computer results.

Use a credential only when your approved environment requires one:

```powershell
$credential = Get-Credential
Get-EFFleetSummary -ComputerName (Get-Content .\computers.txt) -Credential $credential
```

The credential is not stored in the returned report.

## Choose or create a checklist

The built-in checklist is loaded by default:

```powershell
Get-EFBaseline -Name EnterpriseRecommended
```

View available built-in checklists:

```powershell
Get-EFBaseline -ListAvailable
```

Create an editable starter file:

```powershell
New-EFBaseline `
    -Name Contoso.Workstation `
    -Template Starter `
    -Path .\checklists\Contoso.Workstation.json
```

Validate it without checking or changing Windows:

```powershell
Test-EFBaseline -Path .\checklists\Contoso.Workstation.json -PassThru
```

Use it for a read-only check:

```powershell
Get-EFEndpointSummary -Baseline .\checklists\Contoso.Workstation.json -NoProgress
```

Custom checklist files are privileged configuration input. Review them, store them in
source control, and protect them from untrusted writes before an Administrator process
uses them.

### Checklist item types

EndpointForge 0.4.0 understands these types:

- `Registry`
- `Service`
- `FirewallProfile`
- `Defender`
- `WindowsOptionalFeature`
- `BitLocker` (report-only)
- `SecureBoot` (report-only)
- `Tpm` (report-only)

Optional explanation fields are `WhyItMatters`, `HowChecked`, `WhatWouldChange`,
`ManualAction`, `SafetyNotes`, and `RecoveryGuidance`. The included JSON schema documents
the complete structure.

## Commands for scripts

All public commands return objects rather than presentation text unless their names begin
with `Show`.

| Command | Purpose | Changes Windows? |
|---|---|---|
| `Show-EFMenu` | Opens the goal-based guided experience. | Only through the guarded fix flow. |
| `Get-EFEndpointReadiness` | Explains what the current window can check or fix. | No |
| `Get-EFEndpointSummary` | Combines health, inventory, security, and checklist results. | No |
| `Show-EFEndpointSummary` | Displays a summary in plain language. | No |
| `Compare-EFEndpointSummary` | Compares earlier and later checks. | No |
| `Get-EFFleetSummary` | Runs read-only checks on prepared remote computers. | No |
| `Get-EFRemediationPlan` | Separates supported fixes, manual review, and unavailable checks. | No |
| `Invoke-EFEndpointRemediation` | Previews or applies selected supported fixes. | Yes, unless `-WhatIf` |
| `Export-EFEndpointReport` | Writes HTML, JSON, CSV, or CLIXML. | Writes a file |
| `Get-EFBaseline` | Loads or lists checklists. | No |
| `Test-EFBaseline` | Validates a checklist. | No |
| `New-EFBaseline` | Creates a starter checklist and schema. | Writes files |
| `Get-EFComplianceReport` | Returns detailed checklist results. | No |
| `Test-EFEndpointCompliance` | Returns a simple Boolean or detailed checklist result. | No |
| `Get-EFEndpointHealth` | Checks operational health. | No |
| `Get-EFEndpointInventory` | Collects device and security inventory. | No |
| `Get-EFInstalledSoftware` | Lists installed software from uninstall records. | No |
| `Get-EFPendingReboot` | Checks whether Windows reports a pending restart. | No |
| `Get-EFConfiguration` | Reads module session settings. | No |
| `Set-EFConfiguration` | Changes EndpointForge logging and retry settings for the current session. | No Windows setting change |

Use `Get-Help <command> -Full` for parameters and examples.

### Script result codes

The combined check uses stable integer codes:

| Code | Meaning |
|---:|---|
| `0` | Checked items look good. |
| `1` | A warning or partial data needs attention. |
| `2` | A critical issue or checklist difference was found. |
| `3` | One or more required answers could not be collected. |

The terminal only shows these codes in detailed or IT-focused views.

## EndpointForge and DSC

Desired State Configuration (DSC) is a declarative configuration engine: an organization
describes the state machines should have, then an orchestration system applies and
maintains that state. EndpointForge is an operator-focused checkup and guarded-action
tool. Its menu, explanations, reports, and narrow fix receipts are optimized for direct
support and troubleshooting.

EndpointForge does not replace DSC for large-scale continuous configuration. They can be
used together: EndpointForge for understandable diagnosis and evidence, and DSC or another
approved management platform for centrally enforced configuration.

## Troubleshooting

### A setting says Could not check

Run:

```powershell
Get-EFEndpointReadiness
Get-EFEndpointSummary -NoProgress | Show-EFEndpointSummary -Detailed
```

The Windows edition may not include that feature, a security product may own it, or the
information may require **Run as administrator**. EndpointForge reports the uncertainty
instead of guessing.

### A supported fix does not stay changed

Group Policy, Intune, another device-management product, Defender tamper protection, or a
security agent may own the setting. Use the before-and-after receipt, identify the policy
owner, and make the lasting change through that approved system.

### Another computer cannot be reached

Confirm the name, network path, remoting policy, connecting account permission, and that
EndpointForge 0.4.0 or later is installed on the target. The fleet command will not change
those prerequisites for you.

### The menu has no color

Color is disabled when output is redirected, when `NO_COLOR` is set, or when `-NoColor`
is used. The words and ordering remain the same.

## Security and support

Read [SECURITY.md](SECURITY.md) before using privileged fixes or storing reports. Report
security vulnerabilities privately through GitHub Security Advisories or the private
contact documented there. Do not put production reports, credentials, computer names, or
security findings in a public issue.

General bugs and feature requests may be filed in the
[GitHub repository](https://github.com/swaggysnippets/EndpointForge/issues) after removing
sensitive data.

## Development and release verification

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). The repository includes
Pester tests, PSScriptAnalyzer gates, Windows runtime smoke checks, staged-package
verification, GitHub Actions for Windows PowerShell 5.1 and PowerShell 7, and a protected
PowerShell Gallery publishing workflow.

Releases include a SHA-256 file inventory. Authenticode signing is recommended where your
organization requires signed PowerShell modules.

## License

EndpointForge is available under the [MIT License](LICENSE). Copyright 2026 Logan
Bamborough.
