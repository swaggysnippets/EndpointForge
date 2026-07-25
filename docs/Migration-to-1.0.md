# Migrating EndpointForge to 1.0

EndpointForge 1.0 is a contract and hardening release. The recommended migration is an
in-place module upgrade followed by checklist validation, read-only comparison, and a
pilot. It does not require an automatic Windows setting change.

## Before upgrading

1. Record the installed version and source:

   ```powershell
   Get-Module EndpointForge -ListAvailable |
       Sort-Object Version -Descending |
       Select-Object Name, Version, ModuleBase
   ```

2. Save the custom checklist files, wrapper scripts, Intune or Configuration Manager
   deployment content, and any report-processing code in source control.
3. Record every script that parses EndpointForge output, checks an `ExitCode`, uses
   `-AllowNetworkChecks`, or invokes remediation.
4. Save a read-only JSON check from representative pilot computers:

   ```powershell
   Import-Module EndpointForge -RequiredVersion <current-version> -Force
   Get-EFEndpointSummary -NoProgress |
       Export-EFEndpointReport -Path .\before-1.0.json -Force
   ```

5. Do not use production reports as public test fixtures. Remove or replace computer
   names, addresses, software, account, and security information.

## Install the 0.9 contract candidate side by side

PowerShell modules can be installed in versioned directories. Keep the current version
available during the pilot, but import the candidate explicitly so the test is
deterministic:

```powershell
Import-Module EndpointForge -RequiredVersion 1.0.0 -Force
(Get-Module EndpointForge).Version
```

For an offline or centrally managed installation, follow `Enterprise-Deployment.md`.
Verify the package hash inventory, every Authenticode signature, and the expected signer
before importing it in an elevated process.

Do not rely on whichever compatible version PowerShell happens to discover first.

## Validate every checklist

Run validation with the exact 1.0 candidate:

```powershell
$validation = Test-EFBaseline -Path .\Contoso.Endpoint.json -PassThru
$validation

if (-not $validation.IsValid) {
    $validation.Errors
    throw 'The checklist must be corrected before deployment.'
}
```

Then review the checklist itself. Validation limits shape and scope; it does not decide
whether a setting, file, account, IP range, or network destination is appropriate for the
organization.

For a production custom checklist, verify the approved bytes while loading them:

```powershell
$approvedHash = '<64-character-approved-SHA-256>'
$checklist = Get-EFBaseline `
    -Path .\Contoso.Endpoint.json `
    -ExpectedSha256 $approvedHash
```

EndpointForge hashes and parses one locked byte buffer. A custom checklist is limited to
1 MiB and must be valid UTF-8.

During 1.0 preparation, the 0.6.0 built-in `EnterpriseRecommended` checklist validated
under the current 0.9.0 contract-candidate code. Re-run that test against the
final 1.0 artifact. Custom files still require individual validation because they may
contain organization-specific assumptions or undocumented input.

## Changes from 0.6.0

All 20 commands exported by 0.6.0 remain in the 1.0 contract. The newer surface adds:

- `Get-EFManagementAgentHealth`;
- `Invoke-EFManagementAgentAction`.

The checklist catalog grows from 24 types in 0.6.0 to 26:

- `CimNamespaceExists` checks one exact local WMI/CIM namespace without returning WMI
  objects or accepting a query or method;
- `IpAddressInRange` checks active local addresses against canonical IPv4 or IPv6 CIDR
  ranges without contacting another service.

The guided menu adds local Intune and Configuration Manager support. Existing command
names and the technical terms `Baseline` and `ControlId` remain for script compatibility.

### Fleet scripts

Every remote target must have a version that understands every checklist type used by the
fleet run. Use 1.0.0 on all targets for a 1.0 checklist and pin the import in managed
automation.

EndpointForge still does not install itself remotely, enable WinRM, change TrustedHosts,
or run remote fixes.

### Network-active scripts

The network-active set remains:

`TcpPort`, `DnsResolution`, `HttpEndpointHealth`, `WindowsUpdateAvailable`, and
`LocalGroupMembership`.

Calls containing any of these items must include `-AllowNetworkChecks` after the
destinations, identity lookup, update options, source computers, and purpose are approved.
The switch is an acknowledgement, not a network authorization mechanism.

`IpAddressInRange` is local-only and does not use that switch.

## Changes from 0.8.0

The two management-agent commands and the menu support flow remain. The important 1.0
changes are stronger guarantees:

- public commands, typed outputs, status vocabularies, and checklist semantics follow
  `Public-Contract.md`;
- unknown endpoint-health evidence produces `Status = Unknown` and code `3` when it is
  the deciding condition; combined and fleet results use `OverallStatus = Incomplete`
  when incompleteness is decisive, and no required unknown evidence produces code `0`;
- partially collected management-agent evidence is not reported as ready;
- exported CSV values that resemble spreadsheet formulas remain inert data;
- signed release packages are checked against the expected publisher identity;
- exact platform support is limited to the completed certification matrix.

Review any wrapper that previously treated an absent error as success.

## Result-code migration

Do not treat every nonzero result as the same problem:

| Code | Action for automation |
|---:|---|
| `0` | Continue; the requested checked work completed without a finding that needs attention. |
| `1` | Record and route a warning or known local support issue. |
| `2` | Route a critical finding, checklist mismatch, or outstanding change candidate. |
| `3` | Treat the result as incomplete or failed. Do not mark the endpoint healthy or compliant. |

EndpointForge returns codes as object properties; it does not call `exit`. A management
wrapper can translate the property into the smaller code set required by its platform.
For example, Intune detection commonly uses only process code 0 or 1:

```powershell
$result = Get-EFComplianceReport -NoProgress
if ($result.ExitCode -eq 0) {
    exit 0
}

Write-Output "EndpointForge result code: $($result.ExitCode)"
exit 1
```

`Invoke-EFManagementAgentAction` does not expose `ExitCode`. Inspect its `Outcome`,
`IsSuccessful`, `ChangeMayHaveOccurred`, `RequestAccepted`, and
`ImmediateEffectVerified` properties.

## Output-object migration

Use `PSTypeName`, documented properties, status values, and version fields. Do not parse
terminal or menu text.

For JSON consumers:

- accept documented properties in any order;
- ignore new properties that may be added in a 1.x minor release;
- reject an unsupported `SchemaVersion` or `ReceiptVersion`;
- inspect completeness fields before scores;
- preserve dates as ISO 8601 values and do not assume the local time zone;
- keep report data protected in transit and at rest.

The 1.0 contract versions are:

- `EndpointInventory`, `EndpointSummary`, and `FleetSummary`: schema `1.0`;
- `MenuReport` and `MenuSession`: schema `1.2`;
- remediation and management-action receipts: receipt `1.0`.

Objects without an explicit version field follow the EndpointForge module major version.

## Checklist-format migration

`FormatVersion` identifies the EndpointForge checklist file format. New 1.0 checklists
should include the top-level property `"FormatVersion": "1.0"`.

Legacy checklists that omit it are loaded as format 1.0 for compatibility.

`Version` is the checklist author's content version, not the parser version. Increment it
whenever the expected configuration changes.

The 1.0 JSON shape has no `MinimumModuleVersion` property and rejects unknown properties.
Store minimum module requirements in deployment metadata, such as the application package,
assignment, or repository release record.

When adopting either of the newer types, add an item like one of these to the top-level
`Controls` array:

```json
{
  "Id": "EF-CCM-NAMESPACE",
  "Title": "The Configuration Manager information area exists",
  "Type": "CimNamespaceExists",
  "Severity": "Medium",
  "Namespace": "root\\ccm",
  "TimeoutSeconds": 10,
  "DesiredValue": true,
  "Remediable": false,
  "RequiresReboot": false
}
```

```json
{
  "Id": "EF-CORPORATE-NETWORK",
  "Title": "This computer has an address in an approved range",
  "Type": "IpAddressInRange",
  "Severity": "Medium",
  "ApprovedRanges": ["10.20.0.0/16", "2001:db8:1200::/48"],
  "TimeoutSeconds": 10,
  "DesiredValue": true,
  "Remediable": false,
  "RequiresReboot": false
}
```

Use only canonical CIDR networks. Do not place credentials, tokens, scripts, commands,
WQL, or private report data in a checklist.

## Remediation migration

Keep 1.0 deployment read-only until the pilot passes. For every centrally approved fix:

1. Keep the approved `ControlId` list outside the module in reviewed deployment content.
2. Generate a fresh plan.
3. Run `Invoke-EFEndpointRemediation` with the exact IDs and `-WhatIf`.
4. Stop when preview evidence is incomplete.
5. Apply only those previewed IDs from an approved Administrator or `SYSTEM` context.
6. Inspect every receipt, especially `ChangeMayHaveOccurred` and
   `AfterStateWasObserved`.
7. Run a fresh summary and save the before, preview, receipt, and after reports.

EndpointForge does not automatically roll back a Windows change. Installing an earlier
module version does not reverse changes already made by a later version.

## Management-agent migration

Keep management-agent health and actions separate from checklist evaluation.

- `NotDetected` for the Intune Management Extension does not prove that a device is not
  Intune-enrolled.
- `LooksReady` does not prove check-in or management-service health.
- Always run an action with `-WhatIf` first.
- An applied action requires Administrator permission and
  `-AllowManagementTraffic`.
- A Configuration Manager `RequestAccepted` outcome is asynchronous. Confirm the final
  state in the normal administration console.
- Do not loop restarts or policy requests to force immediate convergence.

The 1.0 command still does not accept arbitrary service names, commands, WMI methods,
schedule IDs, remote targets, cache deletion, reset, repair, reinstall, site assignment,
or re-enrollment.

## Pilot acceptance

On each target-certification row:

```powershell
Import-Module EndpointForge -RequiredVersion 1.0.0 -Force

$readiness = Get-EFEndpointReadiness
$after = Get-EFEndpointSummary -NoProgress
$comparison = Compare-EFEndpointSummary -Before .\before-1.0.json -After $after

$readiness
$after | Show-EFEndpointSummary -Detailed
$comparison
```

Accept the pilot only when:

- required information is complete or has an understood, documented limitation;
- no unknown answer is presented as healthy;
- expected 0.6 or 0.8 checklist results are unchanged, or the corrected difference is
  reviewed;
- exported JSON consumers still work;
- `-WhatIf` produces no Windows or management-agent change;
- the approved remediation and management-action scenarios produce truthful receipts;
- report and log permissions match the execution identity.

## Temporary rollback

If 1.0 fails a read-only pilot, stop its assignment and explicitly import the previously
approved module version while the issue is investigated:

```powershell
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module EndpointForge -RequiredVersion <previous-version> -Force
```

Do not use an older version to hide an incomplete or unsafe result. Do not delete the 1.0
evidence until the issue is understood.

For a state-changing failure, follow the receipt's recovery guidance and the
organization's product-specific recovery process. Replacing the module files is not a
Windows setting rollback.
