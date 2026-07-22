# Contributing

Contributions should preserve EndpointForge's automation contracts: Windows PowerShell 5.1 compatibility, structured output, idempotent evaluation, no automatic restarts, no remote code download, and `SupportsShouldProcess` for state changes.

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

Public commands use approved PowerShell verbs and the `EF` noun prefix. Private helpers stay in `Private`; exported commands stay in `Public`. Do not add required runtime dependencies without documenting the operational and supply-chain impact.

## Baseline controls

New remediating control types require:

- a read-only evaluator;
- an idempotent remediator;
- a post-change verification path;
- explicit `-WhatIf` coverage;
- a documented rollback or a clear reason the control is not automatically remediated.

## Release checklist

- Confirm the manifest version, author, description, license, repository metadata, release
  notes, and `CHANGELOG.md` describe the intended release and contain no placeholders.
- Confirm GitHub private vulnerability reporting is enabled and that `SECURITY.md` reflects
  the available private channels using only contact information approved for publication.
- Require successful Windows PowerShell 5.1 and PowerShell 7 CI jobs, including
  PSScriptAnalyzer and Pester.
- Build from the reviewed source and require `Test-StagedModule.ps1` to report
  `HashesVerified = True`; review the packaged `README.md`, `SECURITY.md`, and
  `CONTRIBUTING.md`.
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
