# Enterprise deployment

This guide describes a controlled, offline-capable EndpointForge 1.x deployment for
Intune, Configuration Manager, another endpoint-management platform, or an internal
software repository.

EndpointForge does not install itself on remote computers. The deployment owner packages,
approves, distributes, detects, updates, and removes the module through the organization's
normal software-management process.

## Deployment principles

- Pin one exact EndpointForge version and package hash.
- Obtain the package from the approved release, not from an endpoint at execution time.
- Require Authenticode signatures from the expected publisher, not merely any valid
  signer.
- Install the module and checklist in administrator-controlled locations.
- Begin with read-only evaluation in a pilot ring.
- Keep remediation IDs in a separate, reviewed allowlist.
- Treat network checks and management-agent actions as separately approved traffic.
- Store reports and logs as sensitive endpoint-management data.
- Never place a PowerShell Gallery API key, tenant secret, credential, or signing private
  key in an endpoint package.

## Prepare the release bundle

Use a clean build agent or reviewed workstation:

```powershell
git checkout <reviewed-1.0-commit>
.\build\Test-Module.ps1 -RequireScriptAnalyzer
.\build\Invoke-PesterTests.ps1
.\build\Test-WindowsRuntime.ps1
.\build\Build-Module.ps1 -SkipTests
```

For the production 1.0 release, sign the staged package with an approved code-signing
certificate and an approved Authenticode timestamp service:

```powershell
.\build\Protect-StagedModule.ps1 `
    -ModulePath .\artifacts\EndpointForge `
    -CertificateThumbprint '<approved-code-signing-thumbprint>' `
    -TimestampServer 'http://<approved-authenticode-timestamp-service>'

.\build\Test-StagedModule.ps1 -ModulePath .\artifacts\EndpointForge
.\build\Test-PublishReadiness.ps1 `
    -ModulePath .\artifacts\EndpointForge `
    -RequireSignature `
    -ExpectedSignerThumbprint '<approved-code-signing-thumbprint>'
```

Use the timestamp URL format supported by
[`Set-AuthenticodeSignature`](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/set-authenticodesignature):
the underlying Windows signing API requires an `http://` timestamp endpoint. EndpointForge
then requires a non-empty trusted timestamp certificate on every staged signature, so a
signature created without the requested timestamp cannot pass the stable release gate.

Signing changes file bytes, so the SHA-256 inventory must be produced after signing. Keep
these items together as one immutable release bundle:

- the `EndpointForge` module directory;
- `EndpointForge.sha256.json`;
- release notes and the source commit;
- signer subject, certificate thumbprint, issuer, validity period, and timestamp details;
- software-bill-of-materials and build-provenance evidence when produced by the release
  pipeline.

Do not rebuild the same version on a different machine. PowerShell Gallery package
versions are immutable; any correction needs a new version.

## Verify the bundle at the distribution boundary

The following example verifies that every inventory entry exists and has the recorded
SHA-256 value. Run it before the package enters the deployment system:

```powershell
$moduleRoot = (Resolve-Path .\EndpointForge).Path
$inventory = @(Get-Content .\EndpointForge.sha256.json -Raw | ConvertFrom-Json)

foreach ($entry in $inventory) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $moduleRoot ([string]$entry.Path)))
    $prefix = $moduleRoot.TrimEnd('\') + '\'
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Hash entry escapes the module directory: $($entry.Path)"
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Release file is missing: $($entry.Path)"
    }
    $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    if ($actual -ne [string]$entry.Hash) {
        throw "Release file hash does not match: $($entry.Path)"
    }
}

$actualRelativePaths = @(
    Get-ChildItem -LiteralPath $moduleRoot -Recurse -File |
        ForEach-Object { $_.FullName.Substring($moduleRoot.Length + 1) } |
        Sort-Object
)
$recordedRelativePaths = @($inventory.Path | Sort-Object)
if (Compare-Object $recordedRelativePaths $actualRelativePaths) {
    throw 'The module directory contains missing or unrecorded files.'
}
```

Verify every signable file and the expected certificate identity:

```powershell
$expectedThumbprint = '<approved-code-signing-thumbprint>'
$signable = Get-ChildItem .\EndpointForge -Recurse -File |
    Where-Object Extension -in '.ps1', '.psm1', '.psd1', '.ps1xml'

$bad = @(
    foreach ($file in $signable) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        if ($signature.Status -ne 'Valid' -or
            $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Thumbprint -ne $expectedThumbprint) {
            [pscustomobject]@{
                Path       = $file.FullName
                Status     = $signature.Status
                Thumbprint = $signature.SignerCertificate.Thumbprint
            }
        }
    }
)
if ($bad.Count -gt 0) {
    $bad | Format-Table
    throw 'EndpointForge signature verification failed.'
}
```

Certificate-chain trust and timestamp validation must also succeed under the target
organization's trust policy.

## Choose an installation location

Use a versioned module directory beneath an administrator-controlled, all-users module
path. Resolve approved paths in both hosts rather than assuming one path is visible
everywhere:

```powershell
# Run once in 64-bit Windows PowerShell 5.1 and once in 64-bit PowerShell 7.
$env:PSModulePath -split ';'
```

Typical all-users roots are:

- `C:\Program Files\WindowsPowerShell\Modules` for Windows PowerShell;
- `C:\Program Files\PowerShell\Modules` for PowerShell 7.

The deployed layout must put the manifest directly beneath the version folder:

```text
<approved module root>\
  EndpointForge\
    1.0.0\
      EndpointForge.psd1
      EndpointForge.psm1
      Public\
      Private\
      Data\
      en-US\
      examples\
      docs\
```

If one approved root is deliberately shared by both hosts, verify discovery from each
host during the pilot. Avoid duplicate copies unless the deployment system updates and
detects both as one transaction.

Lock the module directory so standard users cannot replace files that an Administrator or
`SYSTEM` process imports. Verify inherited access with `Get-Acl`.

## Protect custom checklists

A checklist is privileged configuration input even though it cannot contain executable
PowerShell. It can name sensitive settings, files, applications, event logs, identities,
IP ranges, and network destinations, and remediable items can change supported settings.

Store production checklists in a separate administrator-controlled directory, for example:

```text
C:\ProgramData\EndpointForge\Checklists\
```

For each checklist:

1. validate it with the exact deployed module;
2. review all item targets and explanation text;
3. source-control it;
4. record its SHA-256 value or apply an approved signature;
5. verify that integrity before an elevated or `SYSTEM` run;
6. version the checklist's `Version` whenever expectations change.

Use the built-in one-read hash check so the verified bytes are the bytes parsed:

```powershell
$checklist = Get-EFBaseline `
    -Path 'C:\ProgramData\EndpointForge\Checklists\Enterprise.json' `
    -ExpectedSha256 '<64-character-approved-SHA-256>'
```

Pass that returned object, not the path string, to an actual changing operation:

```powershell
Invoke-EFEndpointRemediation -Baseline $checklist -WhatIf -NoProgress
Invoke-EFEndpointRemediation -Baseline $checklist -Confirm:$false -NoProgress
```

EndpointForge blocks an actual custom-checklist fix when the returned object does not show
approved integrity. Do not load elevated code or a checklist from a directory writable by
an untrusted user.

## Detection rule

An enterprise detection rule should establish all of the following:

- the exact expected version is installed in the approved machine path;
- the manifest imports successfully;
- all expected package files are present and no unrecorded file was added;
- hashes match the signed release inventory;
- every signable file has a valid signature from the expected signer;
- the import occurred in the same PowerShell edition and process architecture used by
  production automation.

`Get-Module -ListAvailable` alone is not sufficient because another user-scoped or older
copy can also be discoverable.

After detection, run a no-change smoke:

```powershell
Import-Module '<approved-path>\EndpointForge.psd1' -Force
$module = Get-Module EndpointForge
$readiness = Get-EFEndpointReadiness
$configuration = Get-EFConfiguration

if ($module.Version -ne [version]'1.0.0') {
    throw "Unexpected EndpointForge version: $($module.Version)"
}
if (-not $readiness.IsWindows) {
    throw 'EndpointForge did not identify the Windows host.'
}
```

Keep a full endpoint check out of the installation detection rule when it would make
deployment detection slow or create network activity.

## Intune deployment

Package the verified release bundle, a signed installation script, a signed detection
script, and an optional signed uninstall script as a Win32 application or through the
organization's equivalent managed-content workflow.

Recommended application settings:

- install for the device, using the `SYSTEM` context;
- force a 64-bit PowerShell process on 64-bit Windows;
- copy only the pinned, already-verified offline content;
- install into the approved versioned all-users module directory;
- use the full detection rule above;
- suppress automatic restart;
- deploy to a small evaluation group before wider rings;
- keep the application install separate from compliance assessment and remediation.

The installation command must not call `Install-Module`, `Save-Module`, GitHub, or another
internet endpoint from each managed computer. Acquisition happens once at the trusted
distribution boundary.

For read-only assessment, adapt `examples\Intune\Detect-Compliance.ps1` after pinning
`-RequiredVersion 1.0.0` and the approved checklist path. A management wrapper may map
EndpointForge codes 1, 2, and 3 to its single noncompliant process code, while preserving
the original `ExitCode` in safe output.

For remediation, start from `examples\Intune\Remediate-Compliance.ps1`:

- leave the approved-item list empty until change review is complete;
- maintain the allowlist in deployment content, not in an endpoint-editable location;
- require a fresh successful `-WhatIf` preview;
- apply only IDs actually returned by that preview;
- collect the typed receipt;
- never restart Windows automatically.

Intune script execution commonly uses `SYSTEM`. Remember that application scope
`CurrentUser` then refers to the `SYSTEM` profile, not the signed-in employee.

Installing EndpointForge through Intune is separate from
`Get-EFManagementAgentHealth -Agent Intune`. That health command checks fixed local
Intune Management Extension evidence; it does not prove the Win32 application deployment
or device compliance succeeded.

## Configuration Manager deployment

Use a Configuration Manager Application or the organization's controlled package model.
Distribute the immutable, verified content to approved distribution points.

Recommended deployment properties:

- install for system whether or not a user is signed in;
- use a 64-bit PowerShell process on 64-bit Windows;
- run with administrative rights without user interaction;
- suppress restart and return a normal success/failure code to Configuration Manager;
- use the exact-version, hash, signature, and path detection rule;
- test install, update, repair-detection, and uninstall in a pilot collection;
- keep EndpointForge assessment separate from application installation detection.

For inventory or compliance collection, run the read-only command from a Configuration
Manager baseline, script, or scheduled operation approved by the product owner. Avoid
confusing a Configuration Manager compliance baseline with an EndpointForge checklist:
the former schedules and evaluates management work; the latter is the JSON list of
endpoint expectations.

`Get-EFManagementAgentHealth -Agent ConfigurationManager` reads local client evidence.
`Invoke-EFManagementAgentAction` can preview or request only its fixed allowlisted actions.
Do not trigger those actions as an installation detection rule. Policy requests are
asynchronous and must be confirmed through normal Configuration Manager administration
data.

## Scheduled and RMM execution

For a local scheduled task, RMM job, or similar system:

- import the exact module path or `-RequiredVersion 1.0.0`;
- use 64-bit PowerShell;
- set `$ErrorActionPreference = 'Stop'`;
- use `-NoProgress`;
- write reports and JSONL logs only to an approved directory;
- create that directory with ACLs suitable for the execution identity;
- pass `-AllowNetworkChecks` only for a reviewed checklist and approved sources;
- translate the returned `ExitCode` only at the outermost wrapper.

Example read-only operation:

```powershell
$ErrorActionPreference = 'Stop'
Import-Module EndpointForge -RequiredVersion 1.0.0 -Force

Set-EFConfiguration `
    -LogPath 'C:\ProgramData\EndpointForge\Logs\endpointforge.jsonl' `
    -LogLevel Information

$checklist = Get-EFBaseline `
    -Path 'C:\ProgramData\EndpointForge\Checklists\Enterprise.json' `
    -ExpectedSha256 '<64-character-approved-SHA-256>'

$result = Get-EFEndpointSummary `
    -Baseline $checklist `
    -NoProgress

$result | Export-EFEndpointReport `
    -Path 'C:\ProgramData\EndpointForge\Reports\latest.json' `
    -Force

exit $result.ExitCode
```

Use a distinct approved report name or retention mechanism when historical evidence is
required.

## Network activity controls

Before enabling `-AllowNetworkChecks`, inventory these checklist values:

- TCP host and port;
- DNS name;
- HTTP scheme, host, port, path, method, and redirect choice;
- Windows Update/WSUS scan scope;
- local-group account name or SID;
- every source computer in a fleet assignment.

Confirm authorization with the network, identity, update, and service owners. The switch
does not bypass firewalls, authenticate a service, or suppress network logs.

Do not combine `-AllowNetworkChecks` with
`Invoke-EFManagementAgentAction -AllowManagementTraffic` as though they are one approval.
They describe different activity and need separate review.

## Reports, logs, and retention

Reports and JSONL logs can contain endpoint identity, hardware, local addresses, installed
software, security posture, checklist mismatches, and change evidence.

- Encrypt them in transit and at rest when required.
- Grant access only to operators and services that need it.
- Set an explicit retention period.
- Do not write to a broadly writable share or user-controlled directory.
- Verify the actual ACL as `SYSTEM` or the management-agent identity.
- Do not treat the local JSONL file as tamper-evident; forward it to the organization's
  protected logging platform when audit integrity or centralized retention is required.
- Do not send raw production reports to a public issue or release artifact.

HTML is self-contained but is not anonymous or encrypted. CLIXML should be treated as
trusted PowerShell data, not as content to open from an unknown source.

## Upgrade

Deploy the new version into a new version folder. Keep the previous approved version only
for a bounded rollback window.

1. Verify the new bundle at the distribution boundary.
2. Install it in the pilot ring.
3. Pin pilot assessment to the new version.
4. Validate every custom checklist.
5. Compare representative before and after reports.
6. Expand rings only after the acceptance criteria in `Migration-to-1.0.md` pass.
7. Remove the older version after the rollback window and detection update are complete.

PowerShell can keep an imported module loaded after files change. Start a new host for
clean validation.

## Uninstall

An uninstall should remove only the exact managed version directory and deployment-owned
shortcuts or scheduled definitions. It should not broadly delete:

- other EndpointForge versions;
- organization-authored checklists;
- reports, logs, or change receipts;
- Windows settings previously changed through an approved remediation;
- Intune or Configuration Manager data.

Decide report and checklist retention separately. Installing an older version or removing
the module does not roll back Windows changes.

## Production acceptance

Before moving beyond the pilot:

- complete every platform row claimed in `Compatibility.md`;
- pass Windows PowerShell 5.1 and the declared PowerShell 7 host;
- test standard user, Administrator, and actual `SYSTEM` execution;
- verify clean install, update, detection, and uninstall;
- verify no unknown evidence becomes a healthy result;
- exercise `-WhatIf` and at least one approved reversible remediation;
- test agent absence, stopped/disabled service, interface failure, denied access, and
  timeout scenarios that apply to the environment;
- confirm management traffic and asynchronous results through the normal consoles;
- verify signature enforcement and ACLs on a deployed endpoint;
- complete the 1.0 release checklist.
