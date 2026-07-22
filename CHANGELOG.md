# Changelog

All notable changes use the structure from Keep a Changelog, and versions follow Semantic Versioning.

## [Unreleased]

## [0.3.0] - 2026-07-21

### Added

- Guided `Show-EFMenu` console UI for assessment, findings, planning, remediation preview, guarded apply, baseline selection and creation, and session export.
- Scoped automatic-control selection, mandatory WhatIf preview, exact APPLY acknowledgement, and post-change verification in the interactive remediation flow.
- Accessible ASCII rendering with narrow-console wrapping, `NO_COLOR` support, screen-reader-friendly linear output, and actionable non-interactive-host guidance.
- Optional `EndpointForge.MenuSession` result containing the menu history, errors, cached results, and last exported report path.
- Publish-readiness validation covering public metadata, packaged documentation links, sensitive-file hygiene, local path leaks, and optional Authenticode enforcement.

### Changed

- Interactive operators can now complete the recommended observe, plan, preview, apply, verify, and export workflow without memorizing individual commands.
- Changing or creating the active baseline invalidates cached assessment and remediation data to prevent cross-baseline confusion.
- Release workflows now pin their toolchain, run Pester and staged hash verification before publication, and publish the exact tested artifact.
- Registry controls are restricted to HKLM or HKCU provider paths, and operator-facing baseline text rejects control characters before evaluation.
- Security and contribution policies are included in the Gallery package, with guidance for private vulnerability reporting and sensitive report handling.

## [0.2.0] - 2026-07-20

### Added

- One-command `Get-EFEndpointSummary` assessment and color-aware `Show-EFEndpointSummary` operator dashboard.
- Read-only remediation planning with explicit automatic, manual, blocked, elevation, and reboot outcomes.
- Guided baseline creation, Boolean validation, actionable recommendations, progress displays, and tab completion.
- Coverage and data-completeness reporting that distinguishes unknown evidence from unhealthy endpoint state.

### Changed

- `Test-EFEndpointCompliance` now returns a Boolean by default; rich results moved to `Get-EFComplianceReport` and remain available with `-PassThru`.
- Report dates are normalized to ISO 8601 and JSON/CSV files use UTF-8 without a BOM on PowerShell 5.1 and 7.
- Installed software output is filterable and omits uninstall command lines unless explicitly requested.
- Default formatting and operator guidance now cover inventory, summaries, plans, baseline workflows, and remediation results.

### Fixed

- Sparse uninstall registry entries no longer emit StrictMode property errors.
- Missing baseline paths now produce path-specific errors instead of being interpreted as invalid built-in names.
- Audit-only or incorrectly typed baseline controls are rejected before evaluation or remediation.

## [0.1.0] - 2026-07-20

### Added

- Normalized endpoint, software, reboot, and operational health inventory.
- JSON baseline validation and ten-control `EnterpriseRecommended` baseline.
- Compliance scoring with deterministic automation exit codes.
- Guarded and verified remediation for registry, service, firewall, Defender, and optional-feature controls.
- JSONL logging and JSON, CSV, and CLIXML report export.
- Intune and scheduled-maintenance examples.
- Windows PowerShell 5.1 and PowerShell 7 CI, staging build, and Gallery publishing workflow.
