# EndpointForge

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/EndpointForge?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/EndpointForge)
[![CI](https://github.com/swaggysnippets/EndpointForge/actions/workflows/ci.yml/badge.svg)](https://github.com/swaggysnippets/EndpointForge/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

EndpointForge helps you check and maintain Windows computers without requiring you to
understand configuration frameworks. It answers four practical questions:

- Does this computer look healthy?
- Do important settings, files, recent events, and network paths match the selected
  checklist?
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
Checks health, settings, files, events, and connections; explains problems; and safely previews supported fixes.

1. Check this computer now              [does not change Windows]
2. Understand the latest results        [does not change Windows]
3. Fix selected problems safely         [can change settings after approval]
4. Save reports or compare checks       [creates files only when you choose Save]
5. Check other computers                [no setting changes; TCP items contact named hosts]
6. Change what EndpointForge checks     [does not change Windows]
A. Tools for IT scripts and troubleshooting
H. Help - explain every choice
Q. Exit EndpointForge
```

You can run normal checks as a standard user. Some protected details and all approved
fixes require a PowerShell window opened with **Run as administrator**.

## What EndpointForge can do

- Run one read-only computer check that combines health, restart status, security
  information, and an understandable checklist of things that should be true.
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
| Computer checkup | A non-changing look at health and checklist items. A TCP item can make one brief connection that may be recorded. |
| Checklist | A list of things expected to be true, such as settings, files, recent events, or an available network service. Selecting one does not run it or apply it. |
| Baseline | The script-facing name for a checklist. Existing commands keep this name for compatibility. |
| Checklist item | One expectation in a checklist. Script output calls it a control. |
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

`Get-EFFleetSummary` never changes Windows settings or runs fixes. A checklist containing
TCP items can still create the observable network activity explained below:

```powershell
$fleet = Get-EFFleetSummary -ComputerName PC-101,PC-102
$fleet.Results
$fleet.Failures
```

Before this works, each target computer must already:

- allow PowerShell remoting under your organization's policy;
- have EndpointForge 0.5.0 or later installed;
- allow the connecting account to run the check.

EndpointForge does not install the module remotely, enable WinRM, change TrustedHosts, or
run fixes. Connection failures are returned alongside successful computer results.

A checklist with `TcpPort` items is still read-only, but it is not invisible: every remote
computer will briefly try the named connection, and the destination, firewall, or network
monitoring tools may record each attempt. Fleet checks block these items until you review
the checklist and add `-AllowNetworkChecks`:

```powershell
Get-EFFleetSummary `
    -ComputerName PC-101,PC-102 `
    -Baseline .\checklists\Contoso.EverydayChecks.json `
    -AllowNetworkChecks
```

No application data is sent. A successful connection proves only that a TCP connection
could be opened; it does not test HTTPS, sign-in, or the application itself.

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

To start with the four everyday, report-only examples, use the `EverydayChecks` template:

```powershell
New-EFBaseline `
    -Name Contoso.EverydayChecks `
    -Template EverydayChecks `
    -Path .\checklists\Contoso.EverydayChecks.json
```

Replace every sample file path, search text, event source and ID, and server name before
running it. The packaged [EverydayChecks example](examples/EverydayChecks.json) contains
plain-language explanations beside every property.

Validate it without checking or changing Windows:

```powershell
Test-EFBaseline -Path .\checklists\Contoso.Workstation.json -PassThru
```

Use it for a non-changing check. If it contains TCP items, those named connection attempts
can be recorded by the destination or network:

```powershell
Get-EFEndpointSummary -Baseline .\checklists\Contoso.Workstation.json -NoProgress
```

Custom checklist files are privileged configuration input. Review them, store them in
source control, and protect them from untrusted writes before an Administrator process
uses them.

### Checklist item types

EndpointForge 0.5.0 understands these types:

- `Registry`
- `Service`
- `FirewallProfile`
- `Defender`
- `WindowsOptionalFeature`
- `FileExists` (report-only)
- `FileContainsText` (report-only)
- `WindowsEvent` (report-only)
- `TcpPort` (report-only; makes one observable connection attempt)
- `BitLocker` (report-only)
- `SecureBoot` (report-only)
- `Tpm` (report-only)

Optional explanation fields are `WhyItMatters`, `HowChecked`, `WhatWouldChange`,
`ManualAction`, `SafetyNotes`, and `RecoveryGuidance`. The included JSON schema documents
the complete structure.

The four everyday types all use a Boolean `DesiredValue`: `true` means the named evidence
should be present or the connection should succeed; `false` means it should not. They must
set `Remediable` to `false`. EndpointForge reports the answer and manual guidance, but it
never creates or removes a file, edits a log, writes an event, opens a firewall rule, or
tries to repair a network service.

| Type | What it answers | Main properties and limits |
|---|---|---|
| `FileExists` | Does this exact local file exist? | `Path` is required. Use a full local drive path, optionally with an environment variable such as `%ProgramData%`. Relative paths, network shares, mapped network drives, wildcards, alternate data streams, and paths through links are rejected. A folder does not count as a file. |
| `FileContainsText` | Is this exact text near the end of one local text file? | `Path` and `Text` are required, and the same safe local-path rules apply. `TailLines` defaults to 2,000 and accepts 1 through 10,000. `CaseSensitive` defaults to `false`. `Encoding` defaults to `Utf8` and also accepts `Unicode`, `BigEndianUnicode`, or `Ascii`. The text is an ordinary literal string, not a wildcard or regular expression. |
| `WindowsEvent` | Were enough matching Windows events recorded recently? | `LogName` and `EventIds` are required. `EventIds` can be one whole number from 0 through 65,535 or a list of up to 64 unique IDs. `ProviderName` can narrow the source. `LookbackMinutes` defaults to 60 and accepts up to 10,080 (seven days). `MinimumCount` defaults to 1 and accepts up to 1,000. Use IDs documented for the selected log and source. Protected logs can require **Run as administrator**. |
| `TcpPort` | Can this computer open a TCP connection to one exact host and port? | `HostName` and `Port` are required. `TimeoutMilliseconds` defaults to 3,000 and accepts 100 through 10,000. URLs, paths, and wildcards are rejected. One checklist can contain at most 32 TCP items. |

`FileContainsText` reads only the requested tail, stops with **Could not check** if the file
changes during the read, and refuses a selected tail larger than 8,388,608 decoded
characters. It returns only whether the requested text was found; matching lines are not
placed in results. `WindowsEvent` returns a Boolean answer and bounded count summary;
event messages and event data are not placed in results. The checklist file itself still
contains file paths, search text, event sources, and destinations. Results and reports can
show which paths and destinations were checked and whether they matched. Protect all of
these files according to your organization's data rules.

A missing file is a definite `false` answer for `FileExists`. A missing or unreadable text
file is instead **Could not check**, because EndpointForge has no trustworthy text answer.
An unavailable or protected event log is also **Could not check**. For `TcpPort`, a refused
or timed-out connection is `false`; a host name that cannot be resolved is **Could not
check**. This distinction prevents missing evidence from being treated as success.

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
| `Get-EFFleetSummary` | Runs non-changing checks on prepared remote computers; approved TCP items make observable connections. | No setting change |
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
EndpointForge 0.5.0 or later is installed on the target. The fleet command will not change
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
