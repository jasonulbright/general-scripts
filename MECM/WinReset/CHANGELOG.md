# Changelog

## [1.0.5] - 2026-03-28

### Added
- **Zero-touch remote factory reset** — capture machine state, stage recovery payload, wipe, auto-restore with domain join + cert import + app install + MECM client bootstrap
- `Invoke-PrepareReset.ps1` — orchestrator: captures hostname/OU, generates offline domain join blob, stages everything in C:\Recovery\, triggers factory reset
- `post-setup.ps1` — runs as SYSTEM via SetupComplete.cmd (no temp admin, no auto-logon): applies offline domain join, imports certificates, installs apps in priority order with reboot-resume, starts MECM client
- `unattend-template.xml` — skips all OOBE screens, sets computer name, creates SetupComplete.cmd in specialize pass, includes 24H2 BypassNRO workaround
- `Reset-Config.json` — ordered `InstallSequence` with priority, reboot-after support, and support for .exe, .msi, .bat, .cmd, .ps1, .cer, .pfx file types
- Reboot-resume: tracks progress in registry (`HKLM:\SOFTWARE\WinReset\CurrentStep`), resumes from next step after reboot
- 44 Pester tests covering config validation, XML template, script structure, system prerequisites

### Changed
- `Invoke-FactoryReset.ps1` — added pre-flight check warning if no recovery payload is staged

## [1.0.4] - 2026-03-28

### Added
- Initial release: `Invoke-FactoryReset.ps1` using MDM_RemoteWipe CIM class
- Replaces `systemreset -factoryreset` removed in Windows 24H2
- Support for local and remote targets via PSRemoting
- Confirmation prompt with -Force flag for SCCM deployment
