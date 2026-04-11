# Zero-Touch Remote Factory Reset

Remotely factory reset a Windows device and have it automatically rejoin the domain with the same hostname, reinstall certificates, apps, security software, and the MECM client — zero human interaction.

Replaces full PXE reimaging for device refresh scenarios. Uses the MDM Bridge WMI provider (`MDM_RemoteWipe`) for the reset and `djoin.exe` offline domain join + `unattend.xml` + `SetupComplete.cmd` for automatic post-reset recovery.

## How It Works

**Phase 1 — Prep** (device is online, domain-joined):
1. `Invoke-PrepareReset.ps1` captures the computer name and OU
2. Generates an offline domain join blob via `djoin.exe`
3. Copies certificates, app installers, and scripts to `C:\Recovery\Customizations\`
4. Generates `unattend.xml` (skips OOBE, sets computer name, stages SetupComplete.cmd)
5. Places everything in `C:\Recovery\` (survives factory reset on the OS partition)
6. Triggers `Invoke-FactoryReset.ps1`

**Phase 2 — Auto-restore** (device reboots into OOBE):
1. `unattend.xml` skips all OOBE screens, sets computer name
2. `SetupComplete.cmd` runs `post-setup.ps1` as SYSTEM (before any user logs in)
3. Offline domain join applied, certificates imported, apps installed in priority order
4. If a step requires reboot, the script resumes from the next step on next boot
5. MECM client starts (async), SetupComplete.cmd self-deletes
6. Final reboot — device boots to the login screen, fully configured

No temporary admin accounts. No auto-logon. No passwords in unattend.xml. Everything runs as SYSTEM via SetupComplete.cmd.

## Requirements

| Requirement | Details |
|---|---|
| OS | Windows 10 21H2+ or Windows 11 (including 24H2) |
| Permissions | Local admin on the device |
| Domain Join | Service account with "Join computers to domain" on the target OU |
| Installers | Certificates and app installers available locally or on a network share |
| MECM | Optional — ccmsetup.exe path for client reinstall |
| Power | Laptops must be on AC power |
| Disk space | 20GB+ free on the system drive |
| Reboot state | No pending reboots (Windows Update, CBS, etc.) |

## Setup

### 1. Configure `Reset-Config.json`

Edit for your environment: domain, install sequence (certificates, runtimes, security software, apps), MECM client settings.

### 2. Generate djoin credentials (one-time)

```powershell
# Reuse Export-MECMCredential.ps1 or create djoin-specific credentials
.\Export-MECMCredential.ps1
# Rename output to: djoin.key, djoin.user, djoin.pass
```

### 3. Stage installers

Create an `Installers\` folder next to the scripts. Place all files referenced in `Reset-Config.json`:

```
MECM/WinReset/
    Installers/
        vc_redist.x64.exe
        vc_redist.x86.exe
        windowsdesktop-runtime-8.0.x-win-x64.exe
        CiscoSecureConnect-RootCA.cer
        ZscalerRootCA.cer
        S1-RootCA.cer
        ZscalerConnector.exe
        WindowsSensor.exe
        TeamViewer_Host.msi
```

## Deployment Methods

### SCCM / MECM (fleet-wide or targeted)

1. Create an SCCM **Package** (no program needed initially) with `WinReset\` folder (including `Installers\`) as the source directory
2. Create a **Program** on the package:
   - Command line: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Invoke-PrepareReset.ps1 -Force`
   - Run: Hidden
   - Run with: Administrative rights
   - Allow users to interact: No
3. Distribute content to your DPs
4. Deploy to a device collection (Required or Available depending on your workflow)
5. The device stages everything, wipes, and auto-restores — no user interaction

### Remote Support (single device via TeamViewer)

For a remote user with a broken device where SCCM isn't functional:

1. TeamViewer into the device
2. Copy the entire `WinReset\` folder (with `Installers\`) to `C:\temp\WinReset`
3. Open an **admin PowerShell** on the remote device
4. Run:
   ```powershell
   cd C:\temp\WinReset
   .\Invoke-PrepareReset.ps1 -Force
   ```
5. Disconnect TeamViewer — the device handles the rest
6. TeamViewer Host reinstalls automatically; admin regains access after reset completes

### Homelab Testing

Test the full flow on a test VM without committing to a wipe first:

1. Stage everything without resetting:
   ```powershell
   .\Invoke-PrepareReset.ps1 -SkipReset
   ```
2. Inspect the staged artifacts:
   - `C:\Recovery\AutoApply\unattend.xml` — verify computer name, locale
   - `C:\Recovery\Customizations\post-setup.ps1` — verify script staged
   - `C:\Recovery\Customizations\Reset-Config.json` — verify config
   - `C:\Recovery\Customizations\odjblob.txt` — verify domain join blob
   - `C:\Recovery\Customizations\Installers\` — verify all files present
3. When satisfied, trigger the wipe:
   ```powershell
   .\Invoke-FactoryReset.ps1 -Force
   ```
4. Watch: OOBE skip → SetupComplete.cmd → post-setup.ps1 → reboot(s) → login screen
5. Verify: domain join (`dsregcmd /status`), computer name, certificates, app installs, MECM client

### Quick Reference

```powershell
# Test staging only (no wipe)
.\Invoke-PrepareReset.ps1 -SkipReset

# Full reset with confirmation prompt
.\Invoke-PrepareReset.ps1

# Full reset without prompts (SCCM / scripted)
.\Invoke-PrepareReset.ps1 -Force

# Bare reset without auto-restore (clean OOBE, no automation)
.\Invoke-FactoryReset.ps1 -Force
```

## Install Sequence

The `InstallSequence` array in `Reset-Config.json` controls what gets installed and in what order. Each step has:

| Field | Description |
|---|---|
| `Name` | Display name for logging |
| `InstallerFile` | Filename in the `Installers\` folder |
| `SilentArgs` | Arguments passed to the installer (or cert store name for .cer/.pfx) |
| `ValidationPath` | Path to check after install (optional) |
| `RebootAfter` | If true, reboots and resumes from the next step |
| `Priority` | Execution order (lower = first) |

### Supported file types

| Extension | Behavior | SilentArgs |
|---|---|---|
| `.exe` | Direct execution | Install switches |
| `.msi` | `msiexec /i` | MSI properties |
| `.bat` / `.cmd` | `cmd /c` | Command line args |
| `.ps1` | `powershell -File` | Script parameters |
| `.cer` | Import to cert store | Store name: `Root`, `CA`, `My`, `TrustedPublisher` |
| `.pfx` / `.p12` | `Import-PfxCertificate` | Store name |

### Recommended priority order

| Priority | Category | Examples |
|---|---|---|
| 1-3 | Runtimes | VC++ x64/x86, .NET 8 |
| 5-7 | Certificates | Root CAs for Zscaler, Cisco, SentinelOne |
| 10-15 | Security software | Zscaler, CrowdStrike, SentinelOne |
| 20+ | Management tools | TeamViewer Host |
| Last | MECM client | ccmsetup.exe (async, set `InstallLast: true`) |

## Remote Support Scenario

For a remote user connected via ZPA with a broken MECM client:

1. Admin TeamViewers into the device
2. Copies `WinReset\` folder (with Installers) to `C:\temp\WinReset`
3. Runs: `.\Invoke-PrepareReset.ps1 -Force`
4. Device resets, OOBE skips, certs install, apps install, domain rejoins
5. TeamViewer Host comes back online — admin has remote access
6. User gets a login screen with a fully configured, secured device

No PXE, no USB, no physical access. The prep phase captures everything while ZPA is up; the restore phase is fully offline.

## Homelab Testing

1. Configure `Reset-Config.json` with contoso.com / DC01 / CM01 values
2. Place dummy installers in `Installers\` (or skip app install for first test)
3. Run `Invoke-PrepareReset.ps1 -SkipReset` on the test VM
4. Inspect `C:\Recovery\AutoApply\unattend.xml` and `C:\Recovery\Customizations\`
5. Run `Invoke-PrepareReset.ps1 -Force` on the test VM
6. Watch: OOBE skip → SetupComplete.cmd → post-setup.ps1 → reboot(s) → login screen
7. Verify: domain join, computer name, certificates, app installs, MECM client

## File Structure

```
MECM/WinReset/
    Invoke-FactoryReset.ps1           # MDM_RemoteWipe trigger (with pre-flight check)
    Invoke-PrepareReset.ps1           # Orchestrator: capture, stage, wipe
    post-setup.ps1                    # Post-reset: certs, domain join, apps, cleanup
    unattend-template.xml             # OOBE skip template (parameterized)
    Reset-Config.json                 # Environment configuration
    Invoke-PrepareReset.Tests.ps1     # Pester tests (44 tests)
    README.md                         # This file
    CHANGELOG.md                      # Version history
    Installers/                       # Cert and app installer files (user-provided)
```

## Troubleshooting

### Post-setup log
`C:\Recovery\Customizations\post-setup.log` — full transcript of every step.

### Reboot-resume stuck
Check `HKLM:\SOFTWARE\WinReset\CurrentStep` — shows which step it's on. Reset to 0 and re-run `post-setup.ps1` manually to retry all steps.

### Domain join failed
Check `djoin.exe` exit code in the log. Common causes:
- Blob expired (regenerate with `-SkipReset`)
- Computer account deleted from AD after prep
- OU permissions insufficient for the service account

### OOBE not skipped (24H2)
The unattend includes `BypassNRO` and `HideWirelessSetupInOOBE`. If OOBE still shows a network screen, press Shift+F10:
```cmd
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f
shutdown /r /t 0
```

### Reset won't start
WinRE recovery partition must be intact: `reagentc /info`

## Security

- No temporary user accounts created at any point
- No passwords stored in unattend.xml or registry
- `post-setup.ps1` runs as SYSTEM via SetupComplete.cmd (same as SCCM TS steps)
- `SetupComplete.cmd` self-deletes after execution
- Credential files (`djoin.key/user/pass`) should be NTFS-secured
- `C:\Recovery\Customizations\` — readable by all users; do not store secrets long-term

## Attribution

Factory reset mechanism from [r/SCCM](https://www.reddit.com/r/SCCM/comments/1rv47wj/) community (MDM Bridge WMI approach for Windows 24H2+).
