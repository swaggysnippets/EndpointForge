## What changed

Describe the user-visible and technical changes.

## Why

Explain the problem, root cause, or release requirement this addresses.

## Safety and compatibility

- [ ] Public commands, parameters, output contracts, checklist format, and exit codes were checked.
- [ ] Privileged, network-active, and privacy behavior was reviewed.
- [ ] Documentation and migration guidance were updated where needed.
- [ ] The change does not weaken `WhatIf`, confirmation, elevation, timeout, or integrity controls.

## Validation

- [ ] PSScriptAnalyzer
- [ ] Pester on Windows PowerShell 5.1
- [ ] Pester on PowerShell 7
- [ ] Windows runtime smoke test
- [ ] Staged package and SHA-256 inventory verification
