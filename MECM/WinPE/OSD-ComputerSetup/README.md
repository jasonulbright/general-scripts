# OSD-ComputerSetup

WinPE prestart command that collects a computer role and hostname from the imaging technician before the task sequence runs. No ServiceUI.exe or MDT dependency.

Inspired by [PSAppDeployToolkit v4.1](https://github.com/psappdeploytoolkit/psappdeploytoolkit), which demonstrated that ServiceUI's token manipulation approach is a security risk and unnecessary for most OSD scenarios. In WinPE, the prestart command mechanism provides native user interaction without session-bridging hacks.

## How It Works

The script runs as a **prestart command** on MECM boot media. Prestart commands execute after WinPE boots but before the task sequence selection wizard, and [can interact with the user natively](https://learn.microsoft.com/en-us/mem/configmgr/osd/understand/prestart-commands-for-task-sequence-media) -- no ServiceUI required.

1. WinPE boots via PXE
2. **OSD-ComputerSetup runs** -- shows a WinForms dialog with role selection and hostname input
3. Tech selects a role and enters an 8-character hostname
4. Script validates the hostname against MECM (duplicate check via CIM)
5. Sets task sequence variables (`OSDComputerName`, `OSDDomainOUName`, `OSDComputerRole`, `OSDAppProfile`)
6. Task sequence selection wizard appears
7. TS steps read the variables for domain join, OU placement, and application installs

## Task Sequence Variables Set

| Variable | Description | Example |
|----------|-------------|---------|
| `OSDComputerName` | Sanitized hostname (uppercase, alphanumeric, 8 chars) | `PC00A1B2` |
| `OSDDomainOUName` | LDAP path to the target OU | `LDAP://OU=Desktops,OU=Legal,...` |
| `OSDComputerRole` | Friendly role name | `Legal Desktop` |
| `OSDAppProfile` | App install profile for Install Application steps | `Legal` |

## Hostname Rules

- Alphanumeric only (A-Z, 0-9)
- Forced uppercase on input
- Exactly 8 characters required
- Non-alphanumeric characters blocked at keypress and stripped on paste
- No spaces, BOMs, NBSP, or special characters

## Configuration

### role-map.json

Maps friendly role names (shown to the tech) to LDAP OU paths and app install profiles. Edit this file to match your AD structure:

```json
{
    "Roles": [
        {
            "Name": "Legal Desktop",
            "OUPath": "LDAP://OU=Desktops,OU=Legal,OU=Workstations,DC=contoso,DC=com",
            "AppProfile": "Legal"
        }
    ]
}
```

| Field | Description |
|-------|-------------|
| `Name` | What the imaging tech sees in the dropdown |
| `OUPath` | Full LDAP path written to `OSDDomainOUName` |
| `AppProfile` | Value written to `OSDAppProfile` -- use in TS conditions to control which apps install |

### MECM Hostname Duplicate Check (optional)

The script checks MECM for existing hostnames before accepting. This requires network access from WinPE and credentials:

| File | Description |
|------|-------------|
| `mecm.key` | AES key bytes |
| `mecm.user` | Encrypted username |
| `mecm.pass` | Encrypted password |

Generate these by running `Export-MECMCredential.ps1` (included) on any admin workstation. It prompts for the service account username and password, generates a random AES key, and writes all 3 files. Copy them into the MECM package alongside the script. If credential files are missing, the duplicate check prompts to continue without verification.

Update `$siteServer` and `$siteCode` in OSD-ComputerSetup.ps1 to match your environment.

## Deployment

### 1. Create an MECM Package

Create a standard MECM package (no program needed) with this folder as the source:

```
OSD-ComputerSetup/
    OSD-ComputerSetup.ps1
    OSD-ComputerSetup.bat
    role-map.json
    mecm.key         (optional)
    mecm.user         (optional)
    mecm.pass         (optional)
```

Distribute the package to your distribution points.

### 2. Configure Boot Media

1. **Software Library > Operating Systems > Task Sequences**
2. Right-click > **Create Task Sequence Media** (or edit existing boot image properties)
3. On the **Customization** page:
   - Check **Enable prestart command**
   - Command line: `cmd /C OSD-ComputerSetup.bat`
   - Check **Include files for the prestart command**
   - Select the package created above
4. Complete the wizard and redistribute boot media

### 3. Update Boot Image on DPs

After changing prestart commands, update the boot image on all distribution points. The prestart files are embedded in the WIM.

## WinPE Boot Image Requirements

The boot image must include these optional components:

- WinPE-WMI
- WinPE-Scripting
- WinPE-NetFX
- WinPE-PowerShell

These are required for PowerShell, WinForms, and the CIM hostname check.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success -- variables set, TS proceeds |
| 1 | Failed to initialize TS environment or load config |
| 1630 | User cancelled -- halts task sequence |

## File Structure

```
OSD-ComputerSetup/
    README.md                      # This file
    CHANGELOG.md                   # Version history
    OSD-ComputerSetup.ps1          # Main script (prestart command)
    OSD-ComputerSetup.bat          # Thin wrapper for prestart command line
    role-map.json                  # Role-to-OU mapping (edit for your environment)
    Export-MECMCredential.ps1      # Generates mecm.key/user/pass for hostname duplicate check
```

## Why Not ServiceUI?

ServiceUI.exe (from MDT) works by manipulating Windows security tokens to launch a process in the interactive user's session from SYSTEM context. This approach:

- Requires MDT (end-of-life) as a dependency
- Manipulates security tokens in ways that can be exploited for privilege escalation
- Is unnecessary in WinPE where the prestart command mechanism provides native user interaction

The prestart command approach is Microsoft-documented, supported, and requires no third-party binaries.
