# EndpointForge 1.0 release checklist

EndpointForge 1.0 is a general-availability claim. Feature count alone is not sufficient.
Every required box below needs dated evidence linked from the release record.

The release owner is responsible for stopping publication when evidence is missing or
contradictory.

## Immediate pre-1.0 cleanup

- [ ] The current pre-1.0 work is intentionally committed, reviewed, and merged.
- [ ] The source branch, manifest, changelog, repository default branch, Git tag, GitHub
  release, staged artifact, and PowerShell Gallery show the expected same public version.
- [ ] The repository has no unrelated or unexplained working-tree changes.
- [ ] The public README, packaged help, examples, and Gallery release notes describe the
  code that will actually be published.
- [ ] A clean installation of the latest pre-1.0 release has been exercised before the
  1.0 release candidate begins.

Do not build 1.0 on top of an unpublished collection of local changes.

## Contract freeze

- [ ] The manifest exports exactly the 22 commands listed in `Public-Contract.md`.
- [ ] Public parameter sets, parameter names, accepted types, validation sets, defaults,
  and `ShouldProcess` behavior have contract tests.
- [ ] Every public command has useful synopsis, description, parameter, example, and
  `.OUTPUTS` help.
- [ ] The primary `PSTypeName`, property names, property types, status vocabularies,
  `SchemaVersion`, `ReceiptVersion`, and result-code behavior have snapshot or equivalent
  contract tests.
- [ ] Unknown endpoint-health evidence returns `Status = Unknown` and code `3` when it is
  the deciding condition; combined and fleet results use
  `OverallStatus = Incomplete` when incompleteness is decisive; no required unknown
  evidence returns a healthy result or code `0`.
- [ ] Management-agent readiness requires complete enough local evidence; partial evidence
  is not reported as `LooksReady` or `IsReady = true`.
- [ ] The 26 checklist type names and their required, optional, report-only, network, and
  remediation rules match the JSON schema, runtime validator, help, examples, and
  `Public-Contract.md`.
- [ ] New checklists write `FormatVersion = "1.0"`; legacy files that omit it load as
  format 1.0; unsupported format values are rejected.
- [ ] A valid Baseline Contract 1.0 checklist remains valid across every tested 1.x
  candidate.
- [ ] Display text remains separate from script-facing output; tests do not encourage
  terminal-text parsing.
- [ ] No new public command, checklist type, state-changing action, or result status is
  added after the release-candidate freeze unless the release candidate is restarted.

## Correctness and safety blockers

- [ ] Endpoint health and combined summaries distinguish a known warning/critical finding
  from missing evidence.
- [ ] Compliance scores and coverage do not turn `Error` or `NotApplicable` into a passing
  item.
- [ ] Comparison does not call an incomplete later result an improvement.
- [ ] CSV values that begin with spreadsheet formula characters are exported as inert
  data, with regression tests.
- [ ] Every isolated timeout is a true end-to-end bound or is documented as a narrower
  bound; no action advertises a limit it can substantially exceed.
- [ ] A failed or timed-out remediation or management-agent action truthfully reports
  whether a change may have occurred and whether after-state was observed.
- [ ] Health output identifies sensitive support data accurately and never labels
  identifying management-agent evidence as non-sensitive.
- [ ] An elevated or `SYSTEM` run cannot consume a custom checklist from an untrusted
  writable location in the supported deployment path; integrity is verified by an
  approved signature or pinned hash.
- [ ] Network-active checks still require `-AllowNetworkChecks`.
- [ ] Management-agent actions still require Administrator permission,
  `-AllowManagementTraffic`, `ShouldProcess`, and a bounded timeout.
- [ ] No generic command runner, script text, WQL, arbitrary WMI/CIM method, service name,
  schedule ID, remote action, fleet remediation, cache deletion, reset, reinstall, or
  re-enrollment path is exposed.
- [ ] `-WhatIf` causes no Windows setting change and no management traffic in every
  state-changing workflow.

Any failed item in this section is a release blocker.

## Automated quality gate

Record tool versions in the release evidence.

- [ ] All PowerShell source parses without errors.
- [ ] `Test-ModuleManifest` succeeds and the exported command list matches the manifest.
- [ ] PSScriptAnalyzer reports no warning or error at the pinned version.
- [ ] Pester passes under 64-bit Windows PowerShell 5.1.
- [ ] Pester passes under the exact 64-bit PowerShell 7 version named in the support
  statement.
- [ ] Contract tests cover all public commands and result schemas.
- [ ] A coverage report is retained and reviewed for privileged mutation, validation,
  timeout, privacy, export, and release code. Coverage does not regress without an
  explanation.
- [ ] `build\Test-WindowsRuntime.ps1` runs in CI or another repeatable disposable Windows
  environment under both supported PowerShell hosts.
- [ ] The manually dispatched managed-endpoint certification workflow runs on a protected
  self-hosted disposable lab runner for every management ring claimed; an uploaded
  evidence file identifies the exact Windows and PowerShell versions.
- [ ] The staged module imports in both supported PowerShell hosts.
- [ ] `build\Test-StagedModule.ps1` reports `HashesVerified = True`.
- [ ] `build\Test-PublishReadiness.ps1 -RequireSignature` reports `IsReady = True`.
- [ ] CI uses pinned action commits and pinned release-tool versions.
- [ ] The release workflow either publishes the exact immutable artifact verified by CI,
  or repeats the complete Windows PowerShell 5.1 and PowerShell 7 quality and runtime
  gates against the release tag.

Recommended commands:

```powershell
.\build\Test-Module.ps1 -RequireScriptAnalyzer
.\build\Invoke-PesterTests.ps1 -TestResultPath .\TestResults\pester-5.1.xml
.\build\Test-WindowsRuntime.ps1
.\build\Build-Module.ps1 -SkipTests
.\build\Test-StagedModule.ps1 -ModulePath .\artifacts\EndpointForge
.\build\Test-PublishReadiness.ps1 `
    -ModulePath .\artifacts\EndpointForge `
    -RequireSignature `
    -ExpectedSignerThumbprint '<approved certificate thumbprint>'
```

Run the Pester and runtime commands again from the exact supported PowerShell 7 host.

## Target certification

Complete `Compatibility.md` with exact evidence.

Use `build\Invoke-ManagedEndpointCertification.ps1` to create the standard sanitized
record for each `Unmanaged`, `Intune`, `ConfigurationManager`, and `CoManaged` ring. Its
changing mode requires the exact `I_ACCEPT_MANAGED_ENDPOINT_CHANGES` acknowledgement and
must run only after separate lab change approval.

Before a stable 1.x tag can publish, check the reviewed JSON records into
`release-evidence\v<version>`. `build\Test-ManagedCertificationEvidence.ps1` and the
protected publish workflow require the complete four-ring matrix under Windows PowerShell
(`Desktop`) and PowerShell 7 (`Core`) as StandardUser, Administrator, and SYSTEM: 24
passing records at minimum. Additional certified Windows targets require additional
records. Administrator evidence for every managed ring must include the
approved successful live action for each agent present. Evidence files remain outside the
Gallery module package and must contain only the sanitized fields produced by the helper.

- [ ] Primary supported Windows client, x64, is certified under standard user,
  Administrator, and `SYSTEM`.
- [ ] Every additional Windows client edition/build named in public support text is
  certified.
- [ ] Every Windows Server edition/build named in public support text is certified.
- [ ] Windows PowerShell 5.1 and the exact declared PowerShell 7 version pass on each
  required primary platform.
- [ ] Clean install, versioned update, detection, new-session import, and uninstall pass.
- [ ] Readiness, inventory, health, pending restart, built-in checklist, summary, all
  report formats, and comparison pass against real Windows providers.
- [ ] Every applicable checklist type has at least one known-match, known-mismatch, and
  unavailable/not-applicable acceptance case.
- [ ] Every supported remediation has a no-change preview, approved apply, immediate
  verification, policy-reversion observation where applicable, and documented recovery
  test on a disposable machine.
- [ ] Network denial, refusal, name failure, proxy/TLS failure, provider failure, access
  denial, and timeout cases are truthful.
- [ ] Fleet success, partial failure, unreachable target, wrong version, permission
  failure, and network-fan-out acknowledgement are exercised.

Do not name an uncertified Windows version in the 1.0 support statement.

## Intune and Configuration Manager certification

- [ ] Intune Management Extension absence is not presented as proof of non-enrollment.
- [ ] Intune agent healthy, stopped, disabled, unreadable, and timeout cases are tested
  where reproducible.
- [ ] Configuration Manager client absent, healthy, stopped, disabled, damaged local
  interface, access denied, and timeout cases are tested where reproducible.
- [ ] A co-managed computer returns independent, truthful results for both products.
- [ ] Management-agent health performs no management-service request and does not read log
  contents, policies, applications, scripts, account names, identifiers, or server
  addresses.
- [ ] Start and restart actions are previewed and then tested with approval on disposable
  or pilot computers.
- [ ] Configuration Manager machine-policy request and evaluation report only local
  acceptance; asynchronous completion is confirmed separately through normal
  administration data.
- [ ] Traffic and assigned-work side effects are observed and documented.
- [ ] Timeout after an action starts produces an uncertain/failed receipt with
  `ChangeMayHaveOccurred = true` where appropriate.
- [ ] No management-agent action is available through fleet mode.

## Package signing and supply chain

- [ ] The approved code-signing certificate has an accessible private key, valid code
  signing EKU, acceptable chain, and sufficient remaining validity.
- [ ] The signing private key is protected by the approved key-management process and is
  unavailable to ordinary CI jobs and endpoint packages.
- [ ] An approved Authenticode timestamp service compatible with
  `Set-AuthenticodeSignature` is available.
- [ ] Every staged `.ps1`, `.psm1`, `.psd1`, and `.ps1xml` file is signed.
- [ ] Verification checks `Status = Valid`, the exact approved signer certificate
  identity, and a non-empty trusted timestamp certificate for every signed file.
- [ ] No staged file is signed after the final SHA-256 inventory is generated.
- [ ] The SHA-256 inventory contains every staged file exactly once and no unrecorded file
  is packaged.
- [ ] Source commit, build identity, dependencies, artifact hash, signer, and test results
  are recorded as release provenance.
- [ ] A software bill of materials is attached or linked.
- [ ] The package contains no credential, API key, private key, certificate file, local
  user path, `.env`, JSONL log, test result, or development-only directory.
- [ ] Packaged Markdown links resolve inside the package or use approved HTTPS targets.

Unsigned source builds can remain available for development, but the stable 1.0 Gallery
package must pass the signature gate.

## Documentation and support

- [ ] README and about-help state exactly what EndpointForge can and cannot do.
- [ ] `Compatibility.md` names only certified platforms and the exact tested PowerShell 7
  version.
- [ ] `Public-Contract.md` matches tests and source.
- [ ] `Migration-to-1.0.md` has been followed by at least one 0.6 and one 0.8 pilot where
  those versions are in use.
- [ ] `Enterprise-Deployment.md` has been tested with an offline Intune package and an
  offline Configuration Manager package, or any untested deployment path is clearly
  labeled.
- [ ] README, `SECURITY.md`, `CONTRIBUTING.md`, about-help, examples, and JSON schema link
  to the appropriate 1.0 documentation.
- [ ] All five files in `docs` are included in the staged Gallery package.
- [ ] Every public command has complete help and examples.
- [ ] The changelog describes every security-relevant behavior correction and migration
  concern.
- [ ] Support policy says that the latest stable 1.x receives fixes and explains the
  deprecation window.
- [ ] GitHub private vulnerability reporting is enabled and the approved private contact
  is accurate.
- [ ] Public issues and release evidence contain no production endpoint data.

## Repository and release protection

These controls must be verified in GitHub settings; their presence cannot be inferred
from workflow YAML alone.

- [ ] The default branch is protected against direct unreviewed changes.
- [ ] Required status checks include Windows PowerShell 5.1, PowerShell 7, contract tests,
  and staged-package verification.
- [ ] Review approval is required and stale approvals are dismissed after material
  changes.
- [ ] Release tags are created only from the protected reviewed commit.
- [ ] The `powershell-gallery` environment is protected with a required reviewer.
- [ ] `PSGALLERY_API_KEY` exists only as the protected environment secret, has the minimum
  useful scope, and has been rotated after any possible exposure.
- [ ] Workflow permissions default to read-only and third-party actions are pinned to
  reviewed commits.
- [ ] The publish job rejects a tag that does not exactly equal `v<manifest version>`.
- [ ] Stable 1.x publication rejects missing, incomplete, wrong-version, or failed
  checked-in managed-certification evidence.
- [ ] A prerelease tag or prerelease GitHub release cannot publish a stable Gallery
  package.
- [ ] The release flow does not require publishing the GitHub release before the Gallery
  upload is proven. Use a manual/protected or draft-release flow, then publish the GitHub
  release after Gallery verification.
- [ ] A second publish attempt for the same immutable Gallery version installs that
  version and proves its exact file set and SHA-256 hashes match the staged inventory
  before reusing release evidence; any difference fails safely without creating ambiguous
  artifacts.

## Release-candidate soak

- [ ] A signed 0.9.x release candidate is installed only in evaluation and pilot rings.
- [ ] The public contract and feature set are frozen.
- [ ] The soak duration and minimum endpoint-run count are defined before the soak starts.
- [ ] Pilot coverage includes unmanaged, Intune-managed, Configuration Manager-managed,
  and co-managed computers when those are claimed.
- [ ] Feedback includes operators who were not involved in implementation.
- [ ] Menu tasks can be completed without prior knowledge of DSC, baselines, or the
  technical command vocabulary.
- [ ] No unresolved critical or high-severity correctness, security, data-integrity, or
  false-success issue remains.
- [ ] Every medium issue deferred from 1.0 has an owner, rationale, and public or private
  tracking record as appropriate.
- [ ] Any contract change restarts the release-candidate soak.

## Final version alignment

Immediately before creating the release:

- [ ] `EndpointForge.psd1` says `1.0.0`.
- [ ] release notes and `CHANGELOG.md` say `1.0.0` and contain the final date.
- [ ] the staged manifest says `1.0.0`.
- [ ] the source commit is final and all required checks are green.
- [ ] the tag will be exactly `v1.0.0`.
- [ ] the artifact, hash inventory, signatures, provenance, and SBOM all identify the same
  source and version.
- [ ] GitHub main, the tag, GitHub release, and PowerShell Gallery will contain the same
  intended source state.

## Publication sequence

1. [ ] Freeze the reviewed commit and record its full SHA.
2. [ ] Run every automated and target-certification gate against that commit.
3. [ ] Build, sign, timestamp, regenerate hashes, and verify the immutable artifact.
4. [ ] Create the protected `v1.0.0` tag from that exact commit.
5. [ ] Run the protected publish workflow against the tag.
6. [ ] Confirm PowerShell Gallery reports version `1.0.0`, expected owner, metadata, and
   package hash.
7. [ ] In a clean Windows PowerShell 5.1 session, install exactly 1.0.0 from the Gallery,
   verify signatures and signer identity, import, and run the read-only smoke.
8. [ ] Repeat the clean Gallery install and smoke in the exact supported PowerShell 7
   version.
9. [ ] Confirm all 22 commands and packaged documentation are present.
10. [ ] Publish the GitHub release and mark it latest only after the Gallery package has
    passed the clean-install checks.
11. [ ] Recheck badges, repository links, help links, release notes, and the Gallery page.
12. [ ] Preserve sanitized release evidence and begin normal monitoring.

## Required post-publish smoke

```powershell
Install-Module EndpointForge -RequiredVersion 1.0.0 -Scope CurrentUser
Import-Module EndpointForge -RequiredVersion 1.0.0 -Force

(Get-Module EndpointForge).Version
@(Get-Command -Module EndpointForge -CommandType Function).Count
Get-EFEndpointReadiness
Get-EFEndpointSummary -NoProgress
Get-EFManagementAgentHealth
Invoke-EFEndpointRemediation -WhatIf -Confirm:$false -NoProgress
Invoke-EFManagementAgentAction `
    -Agent Intune `
    -Action RestartAgentService `
    -WhatIf `
    -Confirm:$false
```

Do not enable network-active checklist items or apply an action in a generic
post-publication smoke.

## No-go conditions

Do not publish 1.0 when any of these is true:

- source, tag, artifact, GitHub release, and Gallery versions or commits disagree;
- a critical or high-severity issue is unresolved;
- required unknown evidence can produce success;
- any staged PowerShell file is unsigned, invalid, or signed by an unexpected identity;
- required target-certification evidence is missing;
- either supported PowerShell host fails;
- the release is built from a dirty or unreviewed tree;
- custom privileged checklist integrity is not enforced in the supported deployment;
- the Gallery environment or API key is not protected;
- clean installation from the actual Gallery package has not passed;
- documentation claims an operating system, architecture, agent, or deployment path that
  has not been tested.

## Release evidence record

Attach or link a sanitized record containing:

| Evidence | Value |
|---|---|
| Module version | |
| Source commit | |
| Tag | |
| Artifact SHA-256 | |
| Hash inventory SHA-256 | |
| Signer thumbprint | |
| Timestamp evidence | |
| SBOM/provenance link | |
| Windows PowerShell result | |
| PowerShell 7 version and result | |
| Pester and coverage results | |
| Runtime-smoke results | |
| Target-certification matrix | |
| Release-candidate soak | |
| Security review | |
| Approvers | |
| Gallery clean-install results | |
| GitHub release URL | |
| PowerShell Gallery URL | |
