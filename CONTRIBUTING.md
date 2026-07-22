# Contributing

Contributions should preserve EndpointForge's automation contracts: Windows PowerShell 5.1 compatibility, structured output, beginner-readable presentation, idempotent evaluation, no automatic restarts, no remote code download, and `SupportsShouldProcess` for state changes.

## Development

1. Create a focused branch.
2. Add comment-based help and tests for public behavior.
3. Run `build\Test-Module.ps1 -RequireScriptAnalyzer` and
   `build\Invoke-PesterTests.ps1` in Windows PowerShell 5.1 and PowerShell 7.
4. Run `build\Test-WindowsRuntime.ps1` on a representative Windows endpoint.
5. Run `build\Build-Module.ps1 -SkipTests`, followed by
   `build\Test-StagedModule.ps1`, and inspect the exact staged module.
6. Do not edit files beneath `artifacts` by hand; rebuild to regenerate the package and its
   SHA-256 inventory.
7. Update `CHANGELOG.md` for user-visible changes.
8. Read new menu and help text as if the user has never heard the terms baseline,
   compliance, remediation, DSC, or `WhatIf`; define technical names before using them.

Public commands use approved PowerShell verbs and the `EF` noun prefix. Private helpers stay in `Private`; exported commands stay in `Public`. Do not add required runtime dependencies without documenting the operational and supply-chain impact.

## Baseline controls

New report-only control types require:

- a deterministic, read-only evaluator and clear distinction between a known mismatch and
  a value that could not be checked;
- strict validation of exact targets, bounded work, and tests for invalid, inaccessible,
  changing, and unexpectedly large input;
- beginner-readable `WhyItMatters`, `HowChecked`, `ManualAction`, `SafetyNotes`, and
  privacy wording in the example checklist;
- no automatic remediation, restart request, or suggestion that EndpointForge repaired
  the reported condition; and
- result objects that expose only the evidence needed for the answer. Do not return log
  lines, Windows event messages or payloads, credentials, or application data.

File readers must reject network, relative, wildcard, provider, alternate-data-stream, and
link or reparse-point paths. Keep reads bounded and detect a file that changes during the
read. Event readers must bound the time window, event ID count, and returned count. Network
checks must use exact destinations, a bounded timeout, no retries by default, and no
application payload. Their help, menu, example, validation output, and security guidance
must state that the connection attempt can be observed and recorded.

New remediating control types require:

- a read-only evaluator;
- an idempotent remediator;
- a post-change verification path;
- explicit `-WhatIf` coverage;
- a tested before-and-after receipt and recovery guidance;
- automatic rollback only when it is provably safe across local policy and management
  ownership, otherwise an explicit explanation that rollback is not automatic.

Remote or fleet features must remain read-only unless a separate, explicitly scoped design
is approved. They must not install EndpointForge, enable WinRM, change TrustedHosts, or
retain credentials as a convenience side effect. A fleet run containing network checks
must require explicit operator acknowledgement such as `-AllowNetworkChecks`, explain that
every target becomes a connection source, and test the blocked-by-default behavior.

## Release checklist

- Confirm the manifest version, author, description, license, repository metadata, release
  notes, and `CHANGELOG.md` describe the intended release and contain no placeholders.
- Confirm GitHub private vulnerability reporting is enabled and that `SECURITY.md` reflects
  the available private channels using only contact information approved for publication.
- Require successful Windows PowerShell 5.1 and PowerShell 7 CI jobs, including
  PSScriptAnalyzer and Pester.
- Build from the reviewed source and require `Test-StagedModule.ps1` to report
  `HashesVerified = True`; review the packaged `README.md`, `SECURITY.md`, and
  `CONTRIBUTING.md`, the JSON schema, and every shipped checklist example.
- Require `Test-PublishReadiness.ps1` to report `IsReady = True`. For an enterprise
  signed release, run `Protect-StagedModule.ps1` with an approved certificate and timestamp
  service, then run the readiness check with `-RequireSignature`.
- Protect the `powershell-gallery` GitHub environment, restrict who can approve a release,
  and store `PSGALLERY_API_KEY` only as an environment secret. Never include the key in a
  command transcript, issue, log, commit, or artifact.
- Create a GitHub release whose tag is exactly `v<manifest version>` only after the commit is
  final and required checks pass. Prefer the release-triggered publishing workflow over a
  workstation publish.
- After publication, install the exact version from PSGallery in a clean session and run a
  read-only smoke assessment. Gallery package versions are immutable; fixes require a new
  version.
