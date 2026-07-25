# EndpointForge 1.x public contract

This document defines the automation surface that becomes stable with EndpointForge
1.0.0. Pre-1.0 releases remain previews. The contract applies only after the 1.0 release
gate in `Release-Checklist.md` is complete.

## Compatibility promise

EndpointForge uses Semantic Versioning for the module:

- **Patch releases** fix defects or security problems without intentionally changing a
  valid caller's public command, parameter, result property, status, or checklist meaning.
- **Minor releases** may add commands, optional parameters, result properties, and
  checklist types. Existing properties keep their names, types, and meanings. Automation
  should ignore properties it does not recognize.
- **Major releases** may make incompatible command, result, or checklist changes after
  migration guidance is published.

Removing or renaming a public command or parameter, changing a parameter's accepted type
or default in a way that changes existing calls, removing a result property, changing a
documented property type, reusing a status word for a different meaning, or changing the
meaning of an existing checklist field is a breaking change.

Validation may be tightened in a patch when input was ambiguous, unsafe, outside the
documented grammar, or could produce a false passing result. Such a change must be called
out in the changelog.

Deprecated behavior remains available for at least one subsequent minor release and is
removed only in a major release, except when retaining it would create a material
security or data-integrity risk.

## What scripts should parse

Scripts may rely on:

- exported command and parameter names;
- returned `PSTypeName` values;
- documented property names, primitive types, status values, and result-code meanings;
- `SchemaVersion` or `ReceiptVersion` when present;
- documented JSON checklist fields and validation rules.

Scripts must not parse:

- menu or terminal wording, color, spacing, table layout, progress text, or property
  display order;
- `Summary`, `NextStep`, `Message`, explanation, or recovery prose;
- exception message wording;
- undocumented private functions or the physical layout of `Private`.

Use returned objects for automation and `Show-*` commands for people.

## Public command surface

All 22 commands below are part of the 1.x public surface.

| Command | Stable primary output | Changes state? | Automation convention |
|---|---|---|---|
| `Compare-EFEndpointSummary` | `EndpointForge.EndpointComparison` | No | Read `Changes`, category counts, `IsLikeForLike`, and `AfterCollectionIncomplete`; do not parse explanation prose. |
| `Export-EFEndpointReport` | No output by default; `System.IO.FileInfo` with `-PassThru` | Writes an HTML, JSON, CSV, or CLIXML file after `ShouldProcess` approval | Existing files require `-Force`. The extension or explicit `-Format` selects the representation. CSV formula protection is on by default; the explicit CSV-only unsafe opt-out is not suitable for spreadsheet-bound data. |
| `Get-EFBaseline` | `EndpointForge.Baseline`, or `EndpointForge.BaselineInfo` with `-ListAvailable` | No | A loaded baseline is validated before it is returned. `-ExpectedSha256` verifies the same locked byte buffer that is parsed. |
| `Get-EFComplianceReport` | `EndpointForge.ComplianceReport` | No Windows setting change; approved network-active items can contact named services | Use `Status`, `DataStatus`, counts, `Results`, and `ExitCode`. |
| `Get-EFConfiguration` | `EndpointForge.Configuration` | No | Returns session-local logging and retry settings. |
| `Get-EFEndpointHealth` | `EndpointForge.EndpointHealth` | No | Use `Status`, `DataStatus`, `Checks`, and `ExitCode`. |
| `Get-EFEndpointInventory` | `EndpointForge.EndpointInventory` | No | `SchemaVersion` is `1.0`; use `DataStatus` and `Errors` to judge completeness. |
| `Get-EFEndpointReadiness` | `EndpointForge.EndpointReadiness` | No | A preflight, not an endpoint assessment. Use readiness booleans, `Checks`, and `ControlCapabilities`. |
| `Get-EFEndpointSummary` | `EndpointForge.EndpointSummary` | No Windows setting change; approved network-active items can contact named services | Recommended combined check. `SchemaVersion` is `1.0`; use `OverallStatus`, `DataStatus`, findings, nested reports, and `ExitCode`. |
| `Get-EFFleetSummary` | `EndpointForge.FleetSummary` | No Windows setting change; uses PowerShell remoting and can fan out approved network-active checks | `SchemaVersion` is `1.0`; use `Results`, `Failures`, counts, `IsComplete`, and `ExitCode`. |
| `Get-EFInstalledSoftware` | Zero or more `EndpointForge.InstalledSoftware` objects | No | Reads uninstall records. It does not use `Win32_Product` and does not install, repair, or remove software. |
| `Get-EFManagementAgentHealth` | One or more `EndpointForge.ManagementAgentHealth` objects | No; fixed local evidence only | One object and one `ExitCode` are returned per selected agent. It does not prove enrollment or check-in. |
| `Get-EFPendingReboot` | `EndpointForge.PendingReboot` | No | Use `IsRebootPending`, `DataStatus`, `ErrorCount`, and `Reasons`; partial evidence is not proof that no restart is pending. |
| `Get-EFRemediationPlan` | `EndpointForge.RemediationPlan` | No | Use `Steps`, action counts, `IsReady`, and `ExitCode`. A plan does not approve a change. |
| `Invoke-EFEndpointRemediation` | `EndpointForge.RemediationReport` containing `EndpointForge.RemediationResult` receipts | Yes after `ShouldProcess`; no change under `-WhatIf` | Requires explicit item selection in managed automation. An actual custom-checklist fix requires the object returned by `Get-EFBaseline -ExpectedSha256`; unverified custom files remain available for read-only checks and previews. Use receipt outcomes, before/after evidence, counts, and `ExitCode`. |
| `Invoke-EFManagementAgentAction` | `EndpointForge.ManagementAgentActionResult` | Can change a fixed local service or request fixed management work; no change or traffic under `-WhatIf` | Use `Outcome`, `IsSuccessful`, `ChangeMayHaveOccurred`, `RequestAccepted`, and `ImmediateEffectVerified`. This command does not return an `ExitCode`. |
| `New-EFBaseline` | `EndpointForge.BaselineCreationResult` | Writes a checklist and schema file after `ShouldProcess` approval | Validate and review the created checklist before deployment. |
| `Set-EFConfiguration` | No output by default; `EndpointForge.Configuration` with `-PassThru` | Changes EndpointForge settings only for the current PowerShell process | Supports `ShouldProcess`; it does not change a Windows security setting. |
| `Show-EFEndpointSummary` | No output by default; the original `EndpointForge.EndpointSummary` with `-PassThru` | No | Presentation text is not an automation contract. |
| `Show-EFMenu` | No output by default; `EndpointForge.MenuSession` with `-PassThru` | Only through the separately guarded remediation or management-action workflows | `SchemaVersion` is `1.2`; menu wording and layout can improve in a minor release. |
| `Test-EFBaseline` | `System.Boolean`, or `EndpointForge.BaselineValidation` with `-PassThru` | No | False or `IsValid = false` means the checklist must not be evaluated or remediated. |
| `Test-EFEndpointCompliance` | `System.Boolean`, or `EndpointForge.ComplianceReport` with `-PassThru` | No Windows setting change; approved network-active items can contact named services | Boolean false includes a known mismatch and an unavailable required answer. Use `-PassThru` when the distinction matters. |

`Get-Help <command> -Full` is the authoritative parameter reference for the installed
version. Adding an optional parameter is compatible; changing an existing parameter set
so that a previously valid call becomes ambiguous or invalid is not.

## Result codes

EndpointForge commands do not terminate the hosting PowerShell process. Commands that
provide an `ExitCode` return it as data. A wrapper may call `exit $result.ExitCode` only
when its management system requires a process exit code.

| Code | Stable meaning | Examples |
|---:|---|---|
| `0` | The requested work completed and no checked item requires attention. | Healthy summary, matching checklist, complete fleet with healthy targets, successful verified remediation, or a plan with no candidate. |
| `1` | A non-critical warning, known local support issue, or partial condition needs attention. | Warning health/summary/fleet result or a detected management-agent issue. Not every command uses code 1. |
| `2` | A critical finding, checklist mismatch, or unresolved change candidate exists. | Critical summary, non-matching compliance report, remediation plan with candidates, or verified remediation that leaves a mismatch. |
| `3` | Required evidence or execution is unavailable, blocked, or failed at the command's failure level. | Unknown endpoint health when no known issue outranks it, compliance evaluation error, unreachable or incomplete fleet target, blocked plan, uncertain after-state, or failed remediation. |

Incomplete required evidence prevents a healthy result or code `0`. A known warning or
critical result can retain code `1` or `2` while `DataStatus`, counts, and nested results
also disclose incomplete evidence. A command can skip codes that do not apply to its
domain.

`Invoke-EFManagementAgentAction` uses its typed receipt instead of this integer contract.
Treat only the documented successful outcomes as success, and always inspect
`ChangeMayHaveOccurred` after a failure or timeout.

## Stable status vocabularies

### Checklist item results

`EndpointForge.ControlResult.Status` is one of:

- `Compliant` - the applicable item has the expected answer;
- `NonCompliant` - a trustworthy answer differs from the expected answer;
- `NotApplicable` - the named Windows feature is not used or applicable;
- `Error` - EndpointForge could not obtain a trustworthy answer.

`Error` and `NotApplicable` are different. Neither may be converted into a passing
`Compliant` result.

### Combined and health results

- `EndpointForge.EndpointSummary.OverallStatus`:
  `Healthy`, `Warning`, `Critical`, or `Incomplete`.
- `EndpointForge.EndpointHealth.Status`:
  `Healthy`, `Warning`, `Critical`, or `Unknown`.
- Collection completeness:
  `Complete`, `Partial`, or `Failed` where a command exposes `DataStatus`.
- `EndpointForge.ComplianceReport.Status`:
  `Compliant`, `NonCompliant`, or `Incomplete`.

`Unknown` is the endpoint-health representation when unavailable evidence is decisive.
`Incomplete` is the combined-summary and fleet representation for a result that could not
be completed. Scores describe known evidence; they do not override `DataStatus`,
`UnknownCount`, `ErrorCount`, or `ExitCode`.

### Readiness and comparison

- Readiness checks use `Ready`, `Warning`, or `Blocked`.
- Comparison changes use the documented categories emitted in `Changes`, including
  improvement, newly worse, newly available, could not check, unchanged, and other
  change. Automation should also inspect `ChecklistChanged`, `IsLikeForLike`, and
  `AfterCollectionIncomplete`.

An incomplete later check must not be described as an improvement.

### Management agents

`EndpointForge.ManagementAgentHealth.LocalStatus` is one of:

- `LooksReady`;
- `NeedsAttention`;
- `NotDetected`;
- `CouldNotCheck`.

`LooksReady` requires complete enough fixed local evidence for the implemented decision.
It never means cloud enrollment, site health, or a successful recent check-in.

Management-action receipt outcomes are:

- `WhatIf` or `Skipped` when no action was requested;
- `NotRequired` when the requested local service state already exists;
- `Completed` when an immediate local service action completed and was verified;
- `RequestAccepted` when the fixed Configuration Manager interface accepted an
  asynchronous request;
- `PartiallyChanged` when a change was observed but the operation did not finish cleanly;
- `Failed` when the request failed or its outcome could not be established safely.

`RequestAccepted` is not proof that policy download, evaluation, check-in, or assigned
work completed.

### Remediation receipts

`EndpointForge.RemediationResult.Outcome` is one of:

`NotRequired`, `NotApplicable`, `EvaluationFailed`, `NotRemediable`, `WhatIf`,
`Skipped`, `Changed`, `VerificationFailed`, `PartiallyChanged`, or `Failed`.

Automation must not reduce this to only success/failure. In particular,
`ChangeMayHaveOccurred`, `AfterReadWasAttempted`, and `AfterStateWasObserved` determine
whether recovery review is required.

## Typed object versions

| Object | Version field |
|---|---|
| `EndpointForge.EndpointInventory` | `SchemaVersion = 1.0` |
| `EndpointForge.EndpointSummary` | `SchemaVersion = 1.0` |
| `EndpointForge.FleetSummary` | `SchemaVersion = 1.0` |
| `EndpointForge.MenuReport` | `SchemaVersion = 1.2` |
| `EndpointForge.MenuSession` | `SchemaVersion = 1.2` |
| `EndpointForge.RemediationResult` | `ReceiptVersion = 1.0` |
| `EndpointForge.ManagementAgentActionResult` | `ReceiptVersion = 1.0` |

Objects without an explicit version field follow the module major-version contract.
Within 1.x, existing properties are not removed and their documented types and meanings
do not change. New optional properties may appear in a minor release.

`Data\PublicContract.v1.json` also records the exact exit-code text, all stable status
vocabularies above, and SHA-256 fingerprints of the sorted property-name schema for every
EndpointForge typed object constructed by the module. `build\Test-PublicContract.ps1`
recreates all 29 fingerprints from the PowerShell abstract syntax tree and rejects an
unreviewed result type or property-set change. These are compatibility fingerprints, not
file-integrity signatures.

The stable top-level identity and decision fields are:

- inventory: `SchemaVersion`, `ComputerName`, capture time, normalized operating-system,
  model, storage, network, security, software, `DataStatus`, and errors;
- compliance: checklist identity, evaluation time, `Status`, `IsCompliant`, score,
  coverage, counts, `Results`, and `ExitCode`;
- summary: module and schema versions, computer/checklist identity, all status fields,
  score/coverage/counts, `Findings`, nested reports, and `ExitCode`;
- fleet: checklist identity, target and outcome counts, `IsComplete`, `Results`,
  `Failures`, and `ExitCode`;
- remediation: checklist/correlation identity, outcome counts, reboot and rollback
  flags, typed receipts, and `ExitCode`;
- management actions: receipt/correlation identity, agent/action, timestamps, outcome
  flags, before/after local state, traffic acknowledgement, and recovery fields.

## Checklist JSON contract

The checklist JSON format shipped with 1.0 is **Baseline Contract 1.0**. Its machine-
readable identifier is the optional `FormatVersion` property with the value `"1.0"`.
Checklists created before EndpointForge 1.0 that omit this property are read as format
1.0 for compatibility, and a loaded `EndpointForge.Baseline` exposes
`FormatVersion = "1.0"`. Loaded objects also expose `SourcePath`, `SourceSha256`,
`IntegrityVerified`, and `IntegrityMethod`. `InstalledModulePackage` identifies a bundled
checklist, `ExpectedSha256` identifies bytes matched to an approved hash, and
`UnverifiedCustomFile` is never sufficient for an actual changing operation.

The top-level object requires:

- `Name` - a stable identifier containing letters, numbers, periods, underscores, or
  hyphens;
- `Version` - the checklist author's semantic document version;
- `Description`;
- `Controls` - one through 256 checklist items.

`Version` versions the checklist content. It does not version the EndpointForge parser or
the JSON Schema vocabulary.

`FormatVersion` and `$schema` are optional for legacy compatibility. New 1.0 checklists
should write `"FormatVersion": "1.0"` and use the immutable schema identifier:

```text
https://raw.githubusercontent.com/swaggysnippets/EndpointForge/v1.0.0/Data/Baseline.schema.json
```

An editable offline bundle may instead use its accompanying `Baseline.schema.json`.
Runtime validation remains authoritative because it enforces safety rules that are more
specific than JSON shape alone. A custom checklist file is limited to 1 MiB and must be
valid UTF-8; a UTF-8 byte-order mark is accepted.

Every item requires:

`Id`, `Title`, `Type`, `Severity`, `DesiredValue`, `Remediable`, and `RequiresReboot`.

`Severity` is `Low`, `Medium`, `High`, or `Critical`. Item IDs must be unique. Optional
explanation fields are `Description`, `WhyItMatters`, `HowChecked`, `WhatWouldChange`,
`ManualAction`, `SafetyNotes`, and `RecoveryGuidance`.

Baseline Contract 1.0 supports these 26 type names:

`Registry`, `Service`, `FirewallProfile`, `Defender`, `WindowsOptionalFeature`,
`BitLocker`, `SecureBoot`, `Tpm`, `CimNamespaceExists`, `PendingRestart`, `DiskSpace`,
`WindowsUpdateAvailable`, `DefenderSignatureHealth`, `InstalledApplication`,
`ScheduledTaskHealth`, `ProcessRunning`, `FileExists`, `FileContainsText`,
`FileFreshness`, `WindowsEvent`, `CertificateExpiry`, `TcpPort`, `DnsResolution`,
`HttpEndpointHealth`, `LocalGroupMembership`, and `IpAddressInRange`.

Only `Registry`, `Service`, `FirewallProfile`, `Defender`, and
`WindowsOptionalFeature` can declare a supported automatic fix, and only within their
documented allowlists. The other 21 types must be report-only with `Remediable: false`
and `RequiresReboot: false`.

The five network-active types are `TcpPort`, `DnsResolution`, `HttpEndpointHealth`,
`WindowsUpdateAvailable`, and `LocalGroupMembership`. Evaluation entry points block them
until `-AllowNetworkChecks` is supplied. `IpAddressInRange` performs local-only address
math and is not network-active.

## Checklist evolution rules

- Adding a new checklist type or optional field requires a module minor release and an
  updated schema, help, examples, privacy review, and tests.
- Existing 1.0 fields and types keep their meaning throughout 1.x.
- A new required top-level field, removal or rename of a field or type, incompatible
  grammar change, or changed meaning requires EndpointForge 2.0.
- A safety correction may reject an input that was never valid under the documented
  contract. The changelog must identify the correction and a migration path.
- Because the current JSON shape has no `MinimumModuleVersion` property and rejects
  unknown properties, deployment metadata outside the checklist must record the minimum
  EndpointForge version needed by that checklist.
- `FormatVersion` identifies the file-format contract; `Version` continues to identify
  the checklist author's content revision. Scripts must not substitute one for the other.
- A checklist using a type introduced after 1.0 will be rejected by an older module. Do
  not assume forward compatibility; validate with the exact deployed module version.
- A 1.0 module must continue to validate and run a valid 1.0 checklist throughout 1.x.

Schema validation is necessary but not authorization. An approved owner must still review
paths, settings, applications, jobs, event queries, certificates, identities, CIDR ranges,
and every network destination and purpose.

## File and report formats

- JSON and CSV are UTF-8 without a byte-order mark.
- HTML is self-contained, HTML-encodes values, uses embedded styling, and loads no script,
  font, image, or other internet content.
- CSV cells that could be interpreted as spreadsheet formulas are emitted as data, not
  active formulas.
- CLIXML is intended for trusted PowerShell workflows and can preserve richer .NET type
  information than JSON.
- Existing output files are not overwritten unless `-Force` is supplied.

No report format is anonymous or encrypted. Reports can contain computer names, local
addresses, hardware information, installed software, security findings, and change
evidence.

## Change and recovery contract

Every state-changing public command supports `ShouldProcess` and therefore `-WhatIf`.
EndpointForge never:

- restarts Windows;
- installs Windows updates;
- turns on BitLocker or changes firmware/TPM state;
- downloads and executes remote code;
- enables remoting or runs fleet remediation;
- accepts executable checklist content;
- promises universal automatic rollback.

Remediation records before and after evidence when available. A receipt's recovery text
is guidance, not an executable rollback. Organization policy or another management tool
can replace a local change immediately after it is verified.
