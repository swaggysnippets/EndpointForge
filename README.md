# EndpointForge

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/EndpointForge?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/EndpointForge)
[![CI](https://github.com/swaggysnippets/EndpointForge/actions/workflows/ci.yml/badge.svg)](https://github.com/swaggysnippets/EndpointForge/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

EndpointForge helps you check and maintain Windows computers without requiring you to
understand configuration frameworks. It answers practical questions such as:

- Does this computer look healthy?
- Is a restart waiting, is storage running low, or are Windows updates available?
- Are expected applications, scheduled jobs, files, certificates, Windows management
  information areas, and security settings in place?
- Is this computer on an approved local IP range?
- Can the computer reach approved DNS, TCP, and web services?
- Which problems can EndpointForge safely preview and fix?
- Do the local Microsoft Intune or Configuration Manager support components look ready,
  and which tightly limited support actions are available?
- What changed between an earlier check and a later one?

The guided menu uses everyday language, clearly labels every choice that can change a
setting, and works in Windows PowerShell 5.1 or PowerShell 7 on Windows.

## Start here

Install the current release from the PowerShell Gallery:

```powershell
Install-Module EndpointForge -Scope CurrentUser
```

EndpointForge 0.9 is a preview and the contract candidate for stable 1.0. It is intended
for evaluation and managed pilot rings. The exact 1.0 certification and signing gates
are published in [the release checklist](docs/Release-Checklist.md).

Open the guided menu:

```powershell
Show-EFMenu
```

The first screen is organized around what you want to accomplish:

```text
EndpointForge - Windows computer helper
Checks updates, restarts, storage, security, applications, jobs, files, certificates, events, Windows management information, local network placement, access, and approved connections.

1. Check this computer now              [does not change Windows]
2. Understand the latest results        [does not change Windows]
3. Fix selected problems safely         [can change settings after approval]
4. Save reports or compare checks       [creates files only when you choose Save]
5. Check other computers                [no setting changes; network-active items need approval]
6. Change what EndpointForge checks     [does not change Windows]
7. Help with Intune or Configuration Manager [local checks; approved actions can contact management]
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
- Check fixed local evidence for the Microsoft Intune Management Extension and Microsoft
  Configuration Manager client without contacting either management service.
- Preview or request one named local management-agent support action, with clear traffic,
  permission, and confirmation safeguards.
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
- run an arbitrary command or WMI method, accept a Configuration Manager schedule ID or
  remote action target, or perform a fleet repair;
- reset policy, delete an agent cache, reinstall an agent, remove management data, or
  re-enroll a computer in Intune or Configuration Manager;
- in the guided menu, make an automatic change without item selection, a fresh preview,
  Administrator permission, and the exact `APPLY` acknowledgement;
- in the guided menu, request a management-agent action without a preview, Administrator
  permission, and exact `NETWORK` and `APPLY` acknowledgements;
- apply a supported fix from an unverified custom checklist file; load an approved custom
  checklist with `Get-EFBaseline -ExpectedSha256` before passing it to the fix command;
- promise automatic rollback.

The module records before and after values, but a universal rollback would be unsafe.
Organization policy, later Windows changes, service dependencies, firewall rules, and
other management tools can all affect the setting after EndpointForge runs. Use the
receipt and its recovery guidance with your approved change process.

## Everyday glossary

| Term | Plain-language meaning |
|---|---|
| Computer checkup | A non-changing look at health and checklist items. Network-active items require approval because contacted services or monitoring tools may record the activity. |
| Checklist | A list of things expected to be true, such as settings, storage, applications, jobs, files, certificates, management information, local network placement, recent events, or an available network service. Selecting one does not run it or apply it. |
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
| Management agent | A local Microsoft component that receives and performs work assigned by an organization's Intune or Configuration Manager service. |
| Machine policy | Configuration Manager instructions assigned to a computer. A request asks for current instructions; an evaluation asks the local client to process instructions it already has. |

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

## Help with Intune or Configuration Manager

Intune and Configuration Manager are Microsoft services organizations can use to send
applications, settings, scripts, updates, and other work to Windows computers. EndpointForge
0.8.0 introduced a local support workflow for their Windows agents, and 0.9.0 hardens its
truth, privacy, and timeout guarantees. Open menu option 7 for the
plain-language guided experience.

Check both local agents without changing Windows or contacting a management service:

```powershell
Get-EFManagementAgentHealth
```

Use `-Agent Intune` or `-Agent ConfigurationManager` to check one. The familiar names
`CCM`, `SCCM`, and `ConfigMgr` are also accepted for Configuration Manager. The result reads
only fixed local evidence: service state and startup setting, standard main-log presence and
last-write time, and the fixed local Configuration Manager client interface when applicable.
It never reads log contents, policies, application details, account names, tenant or site
identifiers, device identifiers, or server addresses, and it performs no management traffic.
Optional `-TimeoutSeconds` bounds only the local Configuration Manager interface check;
the default is 10 seconds and the accepted range is 1 through 30.

`LocalStatus` has four possible values:

| Value | Meaning |
|---|---|
| `LooksReady` | The fixed local evidence looks ready. This does not prove a recent or successful check-in. |
| `NeedsAttention` | A known local service, startup, or Configuration Manager interface issue was found. |
| `NotDetected` | The named local agent was not found. |
| `CouldNotCheck` | EndpointForge could not collect trustworthy local evidence. Do not assume the agent is healthy or broken. |

The Intune Management Extension is installed only when the computer is assigned work that
needs it. `NotDetected` for that extension alone is **not** proof that the computer is not
enrolled in Intune.

Preview every support action first:

```powershell
Invoke-EFManagementAgentAction `
    -Agent Intune `
    -Action RestartAgentService `
    -WhatIf
```

An actual request needs PowerShell opened with **Run as administrator**, explicit
`-AllowManagementTraffic`, and normal high-impact PowerShell confirmation. The command
accepts only these fixed combinations:

| Agent | Action | Plain-language effect |
|---|---|---|
| Intune or Configuration Manager | `StartAgentService` | Starts the named local agent service if it is stopped. This can begin a check-in and assigned work. |
| Intune or Configuration Manager | `RestartAgentService` | Restarts the named local agent service. This can interrupt active work, begin a check-in, and start assigned work. |
| Configuration Manager only | `RequestMachinePolicy` | Asks the local client to contact its configured service for current computer instructions. |
| Configuration Manager only | `EvaluateMachinePolicy` | Asks the local client to process computer instructions it has already downloaded. |

For example, after organizational approval:

```powershell
Invoke-EFManagementAgentAction `
    -Agent ConfigMgr `
    -Action RequestMachinePolicy `
    -AllowManagementTraffic
```

Every action can cause management traffic or assigned applications, scripts, policy,
updates, and other work to begin. `-AllowManagementTraffic` records acknowledgement of that
possibility; it is not a network authorization system. Optional `-TimeoutSeconds` bounds
the local wait from 5 through 300 seconds and defaults to 60. A timeout after an action
starts can leave its outcome uncertain. `RequestMachinePolicy` and
`EvaluateMachinePolicy` return when the local client accepts or rejects the request. An
accepted request is asynchronous and does **not** prove that a check-in, download,
evaluation, or assigned task finished successfully. Confirm final device state through the
organization's normal management console and support process.

EndpointForge does not expose arbitrary commands, arbitrary WMI/CIM methods, schedule IDs,
remote targets, fleet actions, policy reset, cache deletion, agent reinstall, or device
re-enrollment. See
[Microsoft's Intune Management Extension guidance](https://learn.microsoft.com/en-us/intune/device-management/tools/management-extension-windows),
the Configuration Manager [`SMS_Client` class](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/client-classes/sms_client-client-wmi-class),
[`RequestMachinePolicy`](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/client-classes/requestmachinepolicy-method-in-class-sms_client),
[`EvaluateMachinePolicy`](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/client-classes/evaluatemachinepolicy-method-in-class-sms_client),
and [Configuration Manager client health checks](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/manage/client-health-checks).

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

An actual fix from a custom checklist requires approved file integrity. Approve its hash
through your normal change process, then load and pass the verified object:

```powershell
$approvedHash = '<64-character approved SHA-256>'
$checklist = Get-EFBaseline -Path .\Contoso.Workstation.json `
    -ExpectedSha256 $approvedHash

Invoke-EFEndpointRemediation -Baseline $checklist -WhatIf -NoProgress
Invoke-EFEndpointRemediation -Baseline $checklist -Confirm:$false -NoProgress
```

Unverified custom checklists can still be validated, checked read-only, and previewed with
`-WhatIf`; EndpointForge blocks their changing operation.

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
`Clixml`. Existing files require `-Force`, and export supports `-WhatIf`. CSV text values
and headings that begin like spreadsheet formulas are neutralized by default. The
`-AllowUnsafeCsvFormulaValues` switch is only for a trusted non-spreadsheet consumer that
requires the original leading characters.

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
network-active items can still create the observable activity explained below:

```powershell
$fleet = Get-EFFleetSummary -ComputerName PC-101,PC-102
$fleet.Results
$fleet.Failures
```

Before this works, each target computer must already:

- allow PowerShell remoting under your organization's policy;
- have a contract-compatible EndpointForge 0.8.0 or later installed;
- allow the connecting account to run the check.

EndpointForge does not install the module remotely, enable WinRM, change TrustedHosts, or
run fixes. Connection failures are returned alongside successful computer results.

Five types are network-active: `TcpPort`, `DnsResolution`, `HttpEndpointHealth`,
`WindowsUpdateAvailable`, and `LocalGroupMembership`. They are report-only, but they are
not invisible. Each remote computer can contact the named TCP destination, name-resolution
service, web address, configured Windows Update or WSUS service, or an identity provider
while resolving the one requested account name. Those services, firewalls, proxies, or
network monitoring tools may record the activity. Local and fleet commands block these
items until you review the checklist and add `-AllowNetworkChecks`:

```powershell
Get-EFFleetSummary `
    -ComputerName PC-101,PC-102 `
    -Baseline .\checklists\Contoso.EverydayChecks.json `
    -AllowNetworkChecks
```

TCP checks send no application data. Name-resolution results omit returned addresses. HTTP
checks send only the configured `HEAD` or `GET` request and do not include response headers
or read the response body. Update scans return only a count. Local-group checks return only
the requested direct-membership answer; supplying an account SID avoids account-name
resolution. A passing network result proves only the exact fact named by its checklist item;
it does not prove authentication or complete application health.

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

To start with editable everyday, report-only examples, use the `EverydayChecks` template:

```powershell
New-EFBaseline `
    -Name Contoso.EverydayChecks `
    -Template EverydayChecks `
    -Path .\checklists\Contoso.EverydayChecks.json
```

Replace every sample application, job, file path, search text, event source and ID,
certificate, account, host, port, web address, management namespace, IP range, and optional
network connection name before running it. The packaged
[EverydayChecks example](examples/EverydayChecks.json) contains plain-language purpose,
safety, manual-action, and recovery guidance for every example.

Validate it without checking or changing Windows:

```powershell
Test-EFBaseline -Path .\checklists\Contoso.Workstation.json -PassThru
```

Use it for a non-changing check. Add `-AllowNetworkChecks` only after reviewing every
network-active item and confirming that each destination, requested account identity,
update option, and purpose is approved:

```powershell
Get-EFEndpointSummary `
    -Baseline .\checklists\Contoso.Workstation.json `
    -AllowNetworkChecks `
    -NoProgress
```

Custom checklist files are privileged configuration input. Review them, store them in
source control, and protect them from untrusted writes before an Administrator process
uses them.

EndpointForge deliberately does not run command lines or PowerShell script text stored in
a checklist. A checklist is configuration data and can be used by an Administrator or
`SYSTEM` process, so allowing raw commands would turn a configuration file into arbitrary
code. Structured item types such as `CimNamespaceExists` provide bounded checks for common
needs without changing that trust boundary.

### Checklist item types

EndpointForge 0.9.0 supports 26 checklist item types. The menu can show this same catalog
without running a check.

| Type | What it answers | Main properties and limits |
|---|---|---|
| `Registry` | Does this Windows setting have the expected value? | `Path` and `ValueName` are required. Only exact `HKLM:` and `HKCU:` paths are accepted. `ValueType` can describe the expected registry data type. |
| `Service` | Is this Windows service configured and running as expected? | `Name` is required. Supply `StartupType`, `Status`, or both. Supported start settings are `Automatic`, `Manual`, and `Disabled`; supported states are `Running` and `Stopped`. |
| `FirewallProfile` | Is Windows Firewall turned on for this network type? | `Name` selects an exact Windows Firewall profile and Boolean `DesiredValue` selects the expected state. |
| `Defender` | Does this Microsoft Defender protection setting match what is expected? | `Property` names the Defender Boolean status to read. The built-in supported fix is limited to real-time protection. Other antivirus ownership can make the item not applicable. |
| `WindowsOptionalFeature` | Is this Windows feature turned on or off as expected? | `Name` is the exact feature name and `DesiredValue` is `Enabled` or `Disabled`. Reading or changing a feature can require Administrator permission. |
| `BitLocker` | Is this drive protected by BitLocker? | `MountPoint` defaults to `%SystemDrive%`; `DesiredValue` is `On`. This item is report-only and never starts encryption. |
| `SecureBoot` | Is Secure Boot turned on? | Boolean `DesiredValue` selects the expected state. Unsupported firmware is reported as not applicable. This item is report-only. |
| `Tpm` | Is the computer security chip present and ready? | `DesiredValue` contains Boolean `TpmPresent` and `TpmReady` values. This item never initializes, clears, or changes the TPM. |
| `PendingRestart` | Does this computer need to restart? | No target property is needed. Set Boolean `DesiredValue` to `false` when no pending restart is expected. EndpointForge checks servicing, Windows Update, pending file replacement, installer, and computer-rename indicators. |
| `DiskSpace` | Does this drive have enough free space? | `Drive` defaults to `%SystemDrive%` and can be one exact fixed local drive letter. Supply `MinimumFreePercent` from 1 through 99, `MinimumFreeGB` from 1 through 1,048,576, or both. When both are present, both thresholds must pass. |
| `WindowsUpdateAvailable` | Is the number of waiting Windows updates within the allowed limit? | `MaximumCount` defaults to 0 and accepts up to 1,000. By default, the scan counts assigned, non-hidden, uninstalled software updates; `IncludeOptional` and `IncludeDrivers` can broaden it. `TimeoutSeconds` defaults to 120 and accepts 10 through 600. Only one update item is allowed per checklist. It requires `-AllowNetworkChecks`. |
| `DefenderSignatureHealth` | Are Microsoft Defender threat definitions recent? | `MaximumAgeDays` defaults to 7 and accepts 0 through 365. If Defender is installed but is not the active antivirus provider, the item is **Not used on this computer** rather than passing. If Defender status cannot be read, the result is **Could not check**. |
| `InstalledApplication` | Does Windows list this application at the expected version? | `ApplicationName` is one exact display name from Windows uninstall records. Optional exact filters are `Publisher` and `ProductCode`. `Scope` is `Machine`, `CurrentUser`, or `All`; `Architecture` is `All`, `x64`, `x86`, or `User`. `Machine` cannot use `User`, while `CurrentUser` cannot use `x64` or `x86`; `All` can be filtered. Use either `ExactVersion` or `MinimumVersion`, not both. Windows Arm requires `Architecture: All`. Wildcards are rejected, and a checklist can contain at most 32 application items. |
| `ScheduledTaskHealth` | Did this scheduled job run successfully and recently? | `TaskName` and `MaximumAgeMinutes` are required; the age accepts 1 through 525,600. `TaskPath` defaults to `\`; `ExpectedLastTaskResult` defaults to 0 and accepts through 4,294,967,295; `RequireEnabled` defaults to `true`. The exact job's enabled state, result, and last-run time are checked. A never-run, missing, inaccessible, or untrustworthy result never silently passes. |
| `ProcessRunning` | Is this program currently running? | `ProcessName` is one exact executable name, with or without `.exe`. Paths, drive names, and wildcards are rejected. A running process alone does not prove application health. |
| `CimNamespaceExists` | Does this Windows management information area exist? | A namespace is a named area Windows and management tools use to organize management information. `Namespace` is required and must be `root` or one exact local path below it, such as `root\ccm`. Each segment begins with a letter and contains only letters, numbers, or underscores. `TimeoutSeconds` defaults to 10 and accepts 1 through 30; at most 32 namespace items are allowed. The result contains a Boolean evidence value and plain-language status, but no WMI objects or provider data. It accepts no server name, credentials, free-form query, command, or script text. Product-specific paths may exist only where that product is installed. Missing is **Does not match**; access, provider, and timeout failures are **Could not check**. |
| `FileExists` | Does this exact local file exist? | `Path` is required. Use a full local drive path, optionally with an environment variable such as `%ProgramData%`. Relative paths, network shares, mapped drives, wildcards, alternate data streams, and paths through links are rejected. A folder does not count as a file. |
| `FileContainsText` | Is the expected text near the end of this log file? | `Path` and literal `Text` are required. `TailLines` defaults to 2,000 and accepts 1 through 10,000. `CaseSensitive` defaults to `false`; `Encoding` defaults to `Utf8` and also accepts `Unicode`, `BigEndianUnicode`, or `Ascii`. |
| `FileFreshness` | Has this file been updated recently? | `Path` and `MaximumAgeMinutes` are required; the age accepts 1 through 525,600. The same exact local-path rules apply. Only file metadata is read, not file contents. |
| `WindowsEvent` | Were enough matching Windows events recorded recently? | `LogName` and `EventIds` are required. Supply up to 64 IDs from 0 through 65,535. `ProviderName` can narrow the source. `LookbackMinutes` defaults to 60 and accepts up to 10,080; `MinimumCount` defaults to 1 and accepts up to 1,000. |
| `CertificateExpiry` | Will this certificate remain valid long enough? | `Thumbprint` is required and must contain exactly 40 hexadecimal characters. `StoreLocation` defaults to `LocalMachine`; `StoreName` defaults to `My` and also accepts `Root`, `CA`, `AuthRoot`, `TrustedPeople`, or `TrustedPublisher`. `MinimumDaysRemaining` defaults to 30 and accepts up to 3,650. Validity is compared in UTC using complete days remaining. |
| `TcpPort` | Can this computer connect to this server and port? | `HostName` and `Port` are required. `TimeoutMilliseconds` defaults to 3,000 and accepts 100 through 10,000. URLs, paths, and wildcards are rejected. It requires `-AllowNetworkChecks`. |
| `DnsResolution` | Can this computer find this server name? | `HostName` must be one absolute, multi-label DNS name, not an IP address or URL. `TimeoutMilliseconds` defaults to 3,000 and accepts 100 through 30,000. EndpointForge performs one time-limited Windows name-resolution operation and returns only a yes-or-no answer, never the resolved addresses. It requires `-AllowNetworkChecks`. |
| `HttpEndpointHealth` | Is this website or web service responding as expected? | `Uri` is one exact HTTP or HTTPS address without credentials, query, fragment, or wildcard. `Method` defaults to `Head` and can be `Get`; `ExpectedStatusCode` defaults to 200 and accepts 100 through 599; `TimeoutMilliseconds` defaults to 5,000 and accepts 100 through 30,000. Redirects are blocked by default; when enabled, at most five safe same-origin redirects are followed. EndpointForge reads the status only, uses normal certificate validation, and sends no explicit credentials or custom headers. It requires `-AllowNetworkChecks`. |
| `LocalGroupMembership` | Is this approved account directly in this local group? | `GroupName` and `MemberName` are exact names or SIDs without wildcards. `TimeoutSeconds` defaults to 15 and accepts 10 through 60. Only direct membership is checked; nested groups are not expanded. EndpointForge resolves only the requested account name, compares SIDs against at most 4,096 direct members, and returns no unrelated identities. Account-name resolution can contact an identity provider, so this item requires `-AllowNetworkChecks`; a direct SID avoids name resolution. Use 64-bit PowerShell on 64-bit Windows. |
| `IpAddressInRange` | Is this computer on an approved IP range? | `ApprovedRanges` is a required JSON array containing 1 through 32 unique IPv4 or IPv6 CIDR networks, such as `10.20.0.0/16` or `2001:db8::/32`. CIDR combines a network address with the number of leading network bits after `/`. Ranges must begin at the network address; `/0`, host names, masks, start-end ranges, wildcards, scoped IPv6, shorthand IPv4, and host bits are rejected. Optional `InterfaceName` narrows the check to one exact active Windows network connection; omit it to consider every active non-loopback physical, virtual, or VPN connection. The answer is `true` when any eligible local address is in any configured range; other local addresses do not fail the item. `TimeoutSeconds` defaults to 10 and accepts 1 through 30. Generated evidence contains a Boolean answer but does not copy detected addresses or `ApprovedRanges` values; author-provided titles and explanations remain visible. This local-only check does not contact a service or require `-AllowNetworkChecks`. At most 16 items are allowed per checklist. |

Optional explanation fields are `WhyItMatters`, `HowChecked`, `WhatWouldChange`,
`ManualAction`, `SafetyNotes`, and `RecoveryGuidance`. The included JSON schema documents
the complete structure.

### Microsoft references

Relevant Microsoft documentation includes Windows Update Agent
[`Search`](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search),
[`Win32_LogicalDisk`](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk),
the [uninstall registry key](https://learn.microsoft.com/en-us/windows/win32/msi/uninstall-registry-key)
and [software-inventory guidance](https://learn.microsoft.com/en-us/powershell/scripting/samples/working-with-software-installations),
[`Get-ScheduledTaskInfo`](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/get-scheduledtaskinfo),
[`Get-MpComputerStatus`](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus),
[`Get-CimInstance`](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance),
the WMI [`__Namespace`](https://learn.microsoft.com/en-us/windows/win32/wmisdk/--namespace) system class,
the [certificate provider](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/about/about_certificate_provider),
[`Get-LocalGroup`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localgroup),
[`NetLocalGroupGetMembers`](https://learn.microsoft.com/en-us/windows/win32/api/lmaccess/nf-lmaccess-netlocalgroupgetmembers),
[`.NET NetworkInterface.GetAllNetworkInterfaces`](https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.networkinterface.getallnetworkinterfaces),
[`IPAddress.GetAddressBytes`](https://learn.microsoft.com/en-us/dotnet/api/system.net.ipaddress.getaddressbytes),
and [.NET Windows name resolution](https://learn.microsoft.com/en-us/dotnet/api/system.net.dns.gethostaddresses).

The new operational types and the existing hardware, file, event, and network types are
report-only: set `Remediable` and `RequiresReboot` to `false`. Most use a Boolean
`DesiredValue`; `true` means the named evidence should be present or healthy and `false`
means it should be absent. `PendingRestart` commonly uses `false`. EndpointForge reports
the answer and manual guidance but does not repair these conditions.

### Privacy and evidence boundaries

- `InstalledApplication` reads current-user and explicit 32-bit or 64-bit uninstall
  registry views and never queries `Win32_Product`, launches repair checks, or installs
  software. Results contain only the bounded match and version evidence needed for the
  answer. If a version comparison was requested but Windows supplies no trustworthy
  comparable version, the result is **Could not check**. This is a check of Windows
  uninstall records, not a complete inventory of portable apps, other user profiles, or
  packages that have no uninstall record.
- `ScheduledTaskHealth` reads enabled state, last run time, and the result code. It never
  returns task actions or arguments and never starts, enables, disables, creates, or edits
  the task.
- `ProcessRunning` returns only whether the exact name was found. It omits process IDs,
  paths, owners, command lines, modules, and process contents.
- `CimNamespaceExists` checks one exact local namespace path segment by segment through
  WMI's `__Namespace` system class. Its evidence value says only whether the path exists. It does not
  return WMI classes, instances, properties, or exception text; accept remote targets,
  credentials, or free-form WQL; call methods; or run checklist-supplied code. A checklist
  can contain at most 32 namespace checks.
- `CertificateExpiry` opens the selected store read-only and compares validity in UTC. It does not return certificate
  subjects, DNS names, raw certificate data, or private-key details, and it never imports,
  exports, renews, or removes a certificate.
- `LocalGroupMembership` resolves only the requested account to a SID, reads direct group
  members as raw SIDs, and returns only the requested relationship. It does not add or
  remove members, expand nested groups, or resolve or return unrelated member names.
- `IpAddressInRange` reads active local connection state inside a bounded worker and performs
  CIDR membership math locally. It does not contact DNS, a gateway, or another service.
  Generated evidence does not copy detected local addresses or `ApprovedRanges` values and
  omits adapter objects, MAC addresses, gateways, DNS settings, and routes. The checklist,
  `Get-EFBaseline`, and author-provided titles or explanation fields still contain whatever
  the author wrote. A Boolean range result is also network-placement evidence, so protect
  both checklists and reports. No more than 16 IP-range items are accepted because
  many narrowly chosen checks could reveal progressively more about local addressing.
- `FileContainsText` reads only the requested tail and stops with **Could not check** if the
  file changes during the read or the selected tail exceeds 8,388,608 decoded characters.
  Matching lines and file contents are not placed in results. `FileFreshness` reads only
  the last-write time.
- `WindowsEvent` returns a Boolean answer and bounded count summary; event messages and
  event data are not placed in results. Protected logs can require **Run as administrator**.

For `InstalledApplication` scope and `CertificateExpiry` store location, `CurrentUser`
means the account that runs EndpointForge. In a management platform that account may be
`SYSTEM`, not the person signed in at the keyboard. On Windows Arm, use
`InstalledApplication` with `Architecture: All`; architecture-specific x64 and x86
filtering is not available.

The checklist file still contains targets such as application names, paths, search text,
event sources, certificate thumbprints, account names, and network destinations. Results
can show which target was checked and whether it matched. Protect checklists and reports
according to your organization's data rules.

### Network-active checks

`TcpPort`, `DnsResolution`, `HttpEndpointHealth`, `WindowsUpdateAvailable`, and
`LocalGroupMembership` require explicit `-AllowNetworkChecks` consent. A checklist can
contain at most 32 network-active items and only one `WindowsUpdateAvailable` item.
Validation confirms safe input shape; it does not decide whether a destination, identity
lookup, or scan is authorized for your organization.

The update item uses the computer's configured Windows Update or WSUS service. By default,
it counts assigned, non-hidden, uninstalled software updates and excludes optional updates
and drivers. It never downloads or installs an update, accepts a license, changes update
settings, or restarts Windows. A scan can start Windows update components, refresh local
scan metadata, contact the configured service, and be recorded. The result contains only
the waiting count, not titles, knowledge-base identifiers, or update metadata.

HTTP checks use normal certificate validation and the configured proxy without proxy
credentials. They send no explicit origin credentials or custom headers, do not include
response headers in results, and do not read the response body. Redirects are blocked
unless the checklist explicitly allows them; when allowed, EndpointForge follows at most
five redirects and only when each address keeps the same scheme, host, and port and has no
credentials, query, fragment, or wildcard. DNS checks perform one time-limited Windows
name-resolution operation for the absolute name and omit returned addresses. TCP checks
send no application data. Local-group checks can contact an organizational identity
provider while resolving the one requested account name; supplying a SID avoids that name
lookup. Contacted services and network monitoring tools can still record the activity.

`IpAddressInRange` is not network-active: it reads local connection state and performs only
local address math, so it does not use `-AllowNetworkChecks`. If connection names are
centrally managed, list them with `Get-NetAdapter | Select-Object -ExpandProperty Name` and
use optional `InterfaceName` to narrow the item. Names can be renamed or localized, so omit
the property when an exact organization-managed name is not reliable.

### Definite differences and unavailable answers

A missing file, freshness target, scheduled task, installed application, process,
certificate thumbprint, WMI/CIM namespace, or direct group membership is a definite `false` answer when Windows
successfully supplied the relevant evidence. A missing or unreadable text file, inaccessible
certificate store, or protected event log is **Could not check** when no trustworthy answer
is available. Unsupported Defender ownership is **Not used on this computer**.

A refused or ordinarily timed-out TCP or HTTP connection and an unresolved DNS name are
known `false` answers when the check itself completes normally. A missing local group or
direct member is also `false` when Windows supplied trustworthy evidence. Permission
failures, unavailable providers or update services, incomplete scans, scan warnings,
ambiguous account-name resolution, and hard worker timeouts are **Could not check**, never
a passing result. Missing or uncertain evidence is not silently treated as success.

A complete local IP snapshot with no address in an approved range is `false`. When an exact
`InterfaceName` is configured but missing, down, loopback-only, or ambiguous, or when local
network enumeration exceeds its safety limit or times out, the item is **Could not check**.

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
| `Get-EFFleetSummary` | Runs non-changing checks on prepared remote computers; approved network-active items can create observable activity. | No setting change |
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
| `Get-EFManagementAgentHealth` | Reads fixed local Intune and Configuration Manager agent evidence without contacting management services. | No |
| `Invoke-EFManagementAgentAction` | Previews or requests one fixed local agent support action. | Can change service state or request management work; no change under `-WhatIf` |
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

### A management-agent action was accepted, but nothing changed yet

An accepted Intune or Configuration Manager request means the local agent accepted the
fixed action. Policy requests and the work they can begin are asynchronous, so this is not
proof of a completed synchronization. Recheck local health, then confirm the device and
assignment status in the organization's management console. Do not repeatedly restart,
reset, reinstall, or clear agent data to force an immediate result.

### Another computer cannot be reached

Confirm the name, network path, remoting policy, connecting account permission, and that a
contract-compatible EndpointForge 0.8.0 or later is installed on the target. The fleet
command will not change those prerequisites for you.

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

Release and enterprise references:

- [Compatibility and certification](docs/Compatibility.md)
- [Public command and checklist contract](docs/Public-Contract.md)
- [Migration to 1.0](docs/Migration-to-1.0.md)
- [Enterprise and offline deployment](docs/Enterprise-Deployment.md)
- [Release checklist](docs/Release-Checklist.md)

## Development and release verification

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). The repository includes
Pester tests, PSScriptAnalyzer gates, Windows runtime smoke checks, staged-package
verification, GitHub Actions for Windows PowerShell 5.1 and PowerShell 7, and a protected
PowerShell Gallery publishing workflow.

Releases include a SHA-256 file inventory, CycloneDX software bill of materials, and
provenance for the release archive. Stable 1.x publication requires every staged
PowerShell file to be timestamp-signed by the expected publisher certificate. Preview 0.x
packages must not be mistaken for satisfying an organization's trusted-publisher policy.

## License

EndpointForge is available under the [MIT License](LICENSE). Copyright 2026 Logan
Bamborough.
