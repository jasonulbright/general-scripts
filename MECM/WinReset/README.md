# Zero-Touch Remote Factory Reset

Remotely factory reset a Windows device and have it automatically rejoin the domain with the same hostname, reinstall critical apps, and bootstrap the MECM client — zero human interaction.

Replaces full PXE reimaging for device refresh scenarios. Uses the MDM Bridge WMI provider (`MDM_RemoteWipe`) for the reset and `djoin.exe` offline domain join + `unattend.xml` for automatic post-reset recovery.

## How It Works

**Phase 1 — Prep** (device is online, domain-joined):
1. `Invoke-PrepareReset.ps1` captures the computer name and OU
2. Generates an offline domain join blob via `djoin.exe`
3. Copies app installers (Zscaler, TeamViewer Host) to `C:\Recovery\Customizations\`
4. Generates `unattend.xml` (skips OOBE, sets computer name, creates temp admin)
5. Places everything in `C:\Recovery\` (survives factory reset)
6. Triggers `Invoke-FactoryReset.ps1`

**Phase 2 — Auto-restore** (device reboots into OOBE):
1. `unattend.xml` skips all OOBE screens, auto-logs in as temp admin
2. `post-setup.ps1` runs: applies domain join, installs apps, starts MECM client
3. Cleans up temp admin, disables auto-logon, reboots
4. Device boots to the login screen — domain-joined, apps installed, same hostname

## Requirements

| Requirement | Details |
|---|---|
| OS | Windows 10 21H2+ or Windows 11 (including 24H2) |
| Permissions | Local admin on the device |
| Domain Join | Service account with "Join computers to domain" on the target OU |
| App Installers | Zscaler/TeamViewer available on a network share or local path |
| MECM | Optional — ccmsetup.exe path for client reinstall |

## Setup

### 1. Configure `Reset-Config.json`

Edit for your environment: domain FQDN, OU, app installer paths, MECM client settings.

### 2. Generate djoin credentials (one-time)

The service account for `djoin.exe /provision` needs encrypted credentials:

```powershell
.\Export-MECMCredential.ps1
# Enter the service account with domain join permissions
# Creates: djoin.key, djoin.user, djoin.pass
```

Rename the output files to `djoin.key`, `djoin.user`, `djoin.pass` (or reuse `mecm.*` files if the same account).

### 3. Stage app installers

Place Zscaler and TeamViewer Host installers on a network share accessible from the target device. Update paths in `Reset-Config.json`.

## Usage

```powershell
# Test staging without resetting (verify artifacts in C:\Recovery\)
.\Invoke-PrepareReset.ps1 -SkipReset

# Full zero-touch reset (interactive confirmation)
.\Invoke-PrepareReset.ps1

# SCCM deployment (no prompts)
.\Invoke-PrepareReset.ps1 -Force

# Standalone reset without auto-restore (bare OOBE)
.\Invoke-FactoryReset.ps1 -Force
```

## Homelab Testing

1. Configure `Reset-Config.json` with contoso.com / DC01 / CM01 values
2. Place dummy installers on a share (or skip app install for first test)
3. Run `Invoke-PrepareReset.ps1 -SkipReset` on CLIENT01
4. Inspect `C:\Recovery\AutoApply\unattend.xml` and `C:\Recovery\Customizations\`
5. Run `Invoke-PrepareReset.ps1 -Force` on CLIENT01
6. Watch: OOBE skip, auto-logon, post-setup.ps1 execution, final reboot
7. Verify: domain join (`dsregcmd /status`), computer name, app installs

## File Structure

```
MECM/WinReset/
    Invoke-FactoryReset.ps1           # MDM_RemoteWipe trigger (with pre-flight check)
    Invoke-PrepareReset.ps1           # Orchestrator: capture, stage, wipe
    post-setup.ps1                    # Post-reset: domain join, apps, cleanup
    unattend-template.xml             # OOBE skip template (parameterized)
    Reset-Config.json                 # Environment configuration
    Invoke-PrepareReset.Tests.ps1     # Pester tests (44 tests)
    README.md                         # This file
    CHANGELOG.md                      # Version history
```

## Troubleshooting

### Post-setup failed
Check the log: `C:\Recovery\Customizations\post-setup.log`

The device will be at a local admin desktop (temp account). Re-run manually:
```powershell
C:\Recovery\Customizations\post-setup.ps1
```

### Domain join failed
Check `djoin.exe` exit code in `post-setup.log`. Common causes:
- Blob expired (regenerate with `Invoke-PrepareReset.ps1 -SkipReset`)
- Computer account deleted from AD after prep
- OU permissions insufficient

### OOBE not skipped (24H2)
The unattend includes `BypassNRO` registry key and `HideWirelessSetupInOOBE`. If OOBE still shows network screen, press Shift+F10 and run:
```cmd
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f
shutdown /r /t 0
```

### Reset fails to start
`MDM_RemoteWipe` requires the WinRE recovery partition to be intact. Verify:
```powershell
reagentc /info
```

## Security Notes

- Temp admin password is randomly generated (16 chars) and embedded in unattend.xml
- The temp account is deleted by a scheduled task on the first real boot
- Auto-logon is disabled by post-setup.ps1 before reboot
- Credential files (djoin.key/user/pass) should be secured with NTFS permissions
- `C:\Recovery\Customizations\` is readable by all users — do not store secrets there long-term

## Attribution

Factory reset mechanism based on the MDM Bridge WMI approach documented in [r/SCCM community](https://www.reddit.com/r/SCCM/comments/1rv47wj/).
