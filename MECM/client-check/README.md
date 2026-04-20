# client-check

A one-click PowerShell tool that generates a self-contained HTML health report for a Windows endpoint and opens it in Edge. Purpose-built for support triage: the end user runs it before submitting a ticket, and the `.html` attaches to the ticket as a snapshot of device state.

## What it reports

| Section | Content |
|---|---|
| Action banner | Big red/amber banner at the top of the page if a reboot is needed (pending-reboot flag detected, or uptime > 24h). If neither, no banner. |
| Summary cards | OS/build, uptime + last boot, pending-reboot status, RAM, lowest free-space %, MECM client version + site code |
| Device | Hostname, DNS name, user, OS caption/version/build, install date, manufacturer/model/serial, domain or workgroup, computer DN (AD), Entra/AzureAD join + tenant |
| Disks | Per-drive free/total/used with a visual bar; colors warn at 85% used, bad at 95% |
| Network adapters (up only) | Interface name, description, MAC, link speed, IPv4, IPv6, gateway, DNS |
| Group Policy | `Machine` and `User` `Registry.pol`: existence, size, last-modified, header signature validation (`PReg` v1). Flags corruption. |
| MECM client | Client version, site code, management point, last policy eval / HW inv / SW inv, cache size, log path |
| MECM log errors | Per-log collapsed sections for 25+ MECM client logs. Green "clean" tag if no errors, red tag with last 15 `type=3` errors per log if present. Unreadable logs tagged "requires admin". |
| Windows event log | Last 24h of Critical/Error/Warning from Application + System. **Elevated only** — skipped with a note when run as standard user. |
| Installed applications | Full 32-bit + 64-bit + per-user enumeration from Uninstall hives. `SystemComponent=1` entries and patches excluded. Scope column distinguishes x64 / x86 / User. |

## Reboot flagging

A reboot banner is shown at the **top** of the report in two cases:

- **Red**: one or more pending-reboot sources detected (CBS, Windows Update auto-update, pending file rename operations, or MECM `CCM_ClientUtilities.DetermineIfRebootPending`).
- **Amber**: uptime > 24 hours with no pending-reboot flag. The device still likely needs a restart before troubleshooting.

The banner reads "ACTION REQUIRED: REBOOT THIS DEVICE" followed by the specific reason(s). End users open the report, see the banner, and know to reboot before calling.

## Output

A single self-contained HTML file at:

```
C:\temp\<USERNAME>_<HOSTNAME>_<yyyyMMdd-HHmmss>.html
```

All CSS is embedded. No external fonts, images, or JS. The file can be attached to a ticket, opened offline, printed, or emailed without dependencies.

## Usage

Double-click the launcher:

```
client-check.cmd
```

Or run the PowerShell directly:

```powershell
.\client-check.ps1                       # writes to C:\temp and opens in Edge
.\client-check.ps1 -NoLaunch             # writes only, no browser
.\client-check.ps1 -OutputDir D:\support # alternate output folder
```

### Running elevated

Standard-user runs cover everything above **except** the Windows event log section and any MECM log files that happen to have ACL restrictions (rare on CCM\Logs, more common under Windows\Logs). Support can right-click > Run as administrator to pull the full set. Sections that were skipped render as greyed rows labelled "requires admin" rather than disappearing, so the reader always knows what was and wasn't captured.

## Requirements

- Windows 10 / 11
- PowerShell 5.1 (ships in-box)
- Microsoft Edge (ships in-box on Windows 11)
- MECM client optional — missing client degrades gracefully to "not installed" rather than erroring

## Deployment

For enterprise rollout to end-user devices, the intended deployment path is:

1. Package via Application Packager
2. Deploy as a MECM Script deployment type
3. Stage the script folder to `C:\ProgramData\client-check\`
4. Create a public desktop shortcut pointing at `client-check.cmd`

No admin required to run, no services, no scheduled tasks. Pure on-demand.

## Design notes

- All gatherers are wrapped in safe-invoke so a single CIM/WMI hiccup does not kill the report — the corresponding card just shows "unknown".
- CMTrace log parsing uses multiline regex on the raw file (`<![LOG[...]LOG]!><time="..." date="..." component="..." type="..." />`) and filters `type=3`. Last 15 errors per log are surfaced, with total error count in the section header.
- All dynamic content is HTML-encoded via `[System.Net.WebUtility]::HtmlEncode` so machine names, app names, and log messages cannot break markup.
- The HTML is generated via `StringBuilder` and written with `UTF8Encoding($false)` — no BOM — so Edge, Outlook, and Markdown-adjacent viewers render cleanly.
