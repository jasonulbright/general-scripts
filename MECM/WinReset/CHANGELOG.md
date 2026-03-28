# Changelog

## [2.0.0] - 2026-03-28

### Added
- **Zero-touch remote factory reset** — full automated pipeline: capture machine state, stage recovery payload, wipe, auto-restore with domain join + app install
- `Invoke-PrepareReset.ps1` — orchestrator that captures hostname/OU, generates offline domain join blob (djoin.exe), stages unattend.xml + apps + post-setup script in C:\Recovery\, then triggers factory reset
- `post-setup.ps1` — runs at first logon after reset: applies offline domain join, installs Zscaler/TeamViewer Host/MECM client, cleans up temp admin, reboots
- `unattend-template.xml` — parameterized unattend.xml that skips all OOBE screens, sets computer name, creates temp admin with single auto-logon, includes 24H2 BypassNRO workaround
- `Reset-Config.json` — environment configuration (domain, apps, MECM client, recovery paths)
- 44 Pester tests covering config validation, XML template, script structure, system prerequisites

### Changed
- `Invoke-FactoryReset.ps1` — added pre-flight check warning if no recovery payload is staged

## [1.0.0] - 2026-03-28

### Added
- Initial release: `Invoke-FactoryReset.ps1` using MDM_RemoteWipe CIM class
- Replaces `systemreset -factoryreset` removed in Windows 24H2
- Support for local and remote targets via PSRemoting
- Confirmation prompt with -Force flag for SCCM deployment
