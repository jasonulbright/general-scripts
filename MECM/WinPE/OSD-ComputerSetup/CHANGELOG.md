# Changelog

## [1.0.0] - 2026-03-28

### Added
- Initial release as a prestart command (no ServiceUI.exe dependency)
- WinForms dialog with role dropdown and hostname input
- Role-to-OU mapping externalized to `role-map.json`
- `OSDAppProfile` variable for role-based application installs
- Hostname sanitization: uppercase, alphanumeric only, exactly 8 characters, paste/IME stripping
- MECM duplicate hostname check via `Get-CimInstance` (replaces deprecated `Get-WmiObject`)
- Encrypted credential support for MECM queries (optional)
- Exit code 1630 on cancel (halts task sequence)

### Changed (from prior ServiceUI-based version)
- Removed ServiceUI.exe dependency -- runs as a WinPE prestart command
- Removed MDT dependency entirely
- Role map moved from inline `[ordered]@{}` hashtable to external `role-map.json`
- Added `AppProfile` field to role map for Install Application step conditions
- Replaced `Get-WmiObject` with `Get-CimInstance`
- Added inline status label for validation feedback (replaces MessageBox-only feedback)
- Hostname input strips pasted non-alphanumeric characters (not just keypress blocking)
