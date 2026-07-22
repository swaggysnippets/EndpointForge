# Changelog

All notable changes use the structure from Keep a Changelog, and versions follow Semantic Versioning.

## [Unreleased]

## [0.5.0] - 2026-07-22

### Added

- Four beginner-friendly, report-only checklist item types: exact local file presence (`FileExists`), literal text near the end of a log (`FileContainsText`), recent Windows event IDs (`WindowsEvent`), and a bounded TCP connection (`TcpPort`).
- An edit-before-use `EverydayChecks` template and `examples/EverydayChecks.json` with plain-language purpose, safety, manual-action, and recovery guidance.
- Readiness, validation, menu, report, comparison, and fleet support for the new Boolean checklist results.
- Explicit `-AllowNetworkChecks` consent before `TcpPort` items can fan out from remote computers.

### Changed

- Checklist explanations now cover things expected to be true, not only Windows settings, and describe how every item is checked before it is run.
- Report-only differences lead to manual guidance instead of incorrectly directing beginners to the safe-fix assistant.
- Fleet targets carrying the new checklist types now require EndpointForge 0.5.0 or later.

### Safety

- File targets are limited to exact local drive paths and reject wildcards, relative paths, providers, alternate data streams, UNC paths, mapped network drives, and existing reparse-point paths.
- Text searches use literal ordinal matching, read at most 10,000 tail lines, and never include matching lines or the requested text in results.
- Event checks return only a Boolean and count summary; event messages, XML, and insertion data are not returned.
- TCP checks make one time-limited connection, send no application data, treat DNS failure as an error, and explain that destinations may record the attempt.

## [0.4.0] - 2026-07-21

### Added

- Goal-based beginner menu for checking a computer, understanding results, safely fixing selected problems, saving and comparing reports, checking prepared remote computers, and managing checklists.
- Read-only `Get-EFEndpointReadiness` preflight that explains platform, permission, remote-session, checklist, provider, and fix availability without evaluating settings.
- Conservative `Compare-EFEndpointSummary` before-and-after comparisons for objects, menu reports, menu sessions, and exported JSON.
- Self-contained, UTF-8 HTML reports with embedded styling, encoded data, and no scripts or external resources.
- Strictly read-only `Get-EFFleetSummary` aggregation for computers that already have PowerShell remoting and EndpointForge configured.
- Plain-language explanation, safety, manual-action, and recovery fields for every built-in checklist item.
- Before/expected/after values, change descriptions, and recovery guidance in fix receipts.

### Changed

- Replaced the flat jargon-heavy menu with nested workflows organized around user goals; the main screen now labels read-only, file-writing, and setting-changing choices.
- Standard-user sessions can complete the mandatory no-change preview before being told how to reopen PowerShell as Administrator.
- Terminal summaries translate internal status values into everyday language and reserve item IDs and script result codes for detailed or IT views.
- Remediation plans and results describe who can act, why an item matters, what would change, restart impact, and what was observed before and after.
- The built-in checklist and JSON schema now support optional explanation and recovery fields.
- Documentation now defines checklist, baseline, control, compliance, preview, and remediation before using the technical terms.

### Safety

- Comparisons never call missing or unreadable later evidence an improvement and warn when computer identity or checklist version differs.
- Fleet checks never install the module, enable remoting or TrustedHosts, retain credentials, or invoke fixes.
- EndpointForge explicitly records that receipts are not automatic rollback guarantees because policy and later Windows changes can own a setting.
- The unattended Intune example starts with an empty deployment approval list and requires a fresh successful preview before applying listed items.

### Fixed

- A supported fix that changes one value before a later step fails now performs a follow-up read and records the observed partial change instead of showing the earlier value as the after-state.
- Blocked readiness values render as one plain-language status in HTML reports.

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
