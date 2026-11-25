# Scanner Inventory

Catalog scanners connected to workstations, two ways:

| Tool | Use it for |
|--|--|
| [`Get-ConnectedScanners.ps1`](Get-ConnectedScanners.ps1) | ConfigMgr **Run Scripts**. Authoritative: live device tree, vendor tagging, catches scanners with no driver. |
| [CMPivot queries](#cmpivot) (below) | Quick look across a collection, including cached data for offline clients. |

Target brands are Fujitsu (fi-series / ScanSnap), Canon, Lexmark, and Ricoh. Other brands are still listed, tagged `Other`.

## Run Scripts: Get-ConnectedScanners.ps1

1. **Software Library > Scripts > Create Script**, import the file, approve it.
2. Right-click a collection or device > **Run Script**.
3. Read results in **Monitoring > Script Status**.

No parameters. Read-only. Runs as SYSTEM. Needs Windows PowerShell 3.0+.

### Output

| Output | Exit code | Meaning |
|--|--|--|
| `No scanners found` | 0 | Nothing matched. Identical text, so ConfigMgr groups these devices into one bar. |
| JSON array | 0 | One object per scanner. |
| `ERROR: <message>` | 1 | The WMI query or the script failed on that device. |

JSON fields:

| Field | Value |
|--|--|
| `Vendor` | `Fujitsu`, `Canon`, `Lexmark`, `Ricoh`, or `Other` |
| `Model` | Device name as shown in Device Manager |
| `Mfr` | Manufacturer string from the driver |
| `Match` | `Image` = in the Imaging device class. `NoDriver` = driver missing (problem code 28) but identified as one of the four brands. |
| `Bus` | First segment of the device ID: `USB`, `SWD` (WSD / network), etc. |
| `VidPid` | USB vendor:product ID, e.g. `04C5:114F`. Blank if not USB. |
| `Serial` | USB serial number if the device reports one. Blank otherwise. |
| `Status` | WMI status, normally `OK` or `Error` |
| `Err` | Device Manager problem code. `0` = working, `28` = no driver. |
| `Service` | Driver service, e.g. `usbscan`, `WSDScan` |
| `Id` | PnP device ID. Unique key for de-duplication. |

Example:

```json
[{"Vendor":"Fujitsu","Model":"fi-6130","Mfr":"FUJITSU","Match":"Image","Bus":"USB","VidPid":"04C5:114F","Serial":"","Status":"OK","Err":0,"Service":"usbscan","Id":"USB\\VID_04C5&PID_114F\\5&2A1B&0&2"}]
```

Windows PowerShell 5.1 writes `&` as `\u0026` inside JSON. That is valid JSON and decodes back to `&`.

ConfigMgr truncates script output at 4 KB. The script stops early and ends the array with `{"Truncated":"<n> more not shown"}`, so a cut-off result is visible and still parses. About 18 scanners fit.

### Settings (top of the script)

| Variable | Default | Effect |
|--|--|--|
| `$KnownVendorsOnly` | `$false` | `$true` drops everything tagged `Other`. |
| `$VendorRules` | four brands | Name regex and USB vendor IDs per brand. First match wins. |

### What it cannot see

Read this before treating `No scanners found` as proof.

- **Powered-off or unplugged scanners.** Only devices present at run time are reported. Sheet-fed scanners that auto power off leave the USB bus. Run during working hours and re-run.
- **Network MFPs without a WSD scan device.** Vendor network-TWAIN drivers and scan-to-email / scan-to-folder create no PnP device on the workstation.
- **Offline clients.** Run Scripts only reaches online clients and times out after one hour.
- **Webcams** are skipped on purpose (`Service = usbvideo`). A webcam on a non-standard driver in the Imaging class shows up as `Other`.
- **Driverless devices of other brands.** `NoDriver` rows are limited to the four brands, otherwise every unknown device in the fleet would be listed. A driverless Canon *printer* can appear as `NoDriver`; check `Model`.

Brand note: Ricoh now owns the fi-series / ScanSnap line. Anything named `fi-xxxx` or `ScanSnap` is tagged `Fujitsu` whatever the label says.

### Troubleshooting a failed device

| Symptom | Check |
|--|--|
| Exit code 1, `ERROR: ...` | The message is the WMI error. Test on the device: `Get-CimInstance Win32_PnPEntity \| Measure-Object`. A broken WMI repository is the usual cause. |
| No result for a device | Client offline or the one-hour window passed. Run again. |
| Script never ran | Client log `C:\Windows\CCM\Logs\Scripts.log`. Antimalware blocking `%windir%\CCM\ScriptStore` is a known cause. |
| Known scanner missing | Was it powered on? In Device Manager, is it under **Imaging devices**? A working device filed under a different class is out of scope by design. A driverless one is only caught if its name or USB vendor ID is in `$VendorRules`. |

## CMPivot

CMPivot has no dedicated scanner entity. `PNPDEVICEDRIVER` ("PNP Device Driver") is the hardware-inventory class built on `Win32_PnPEntity`, so its columns are that class's property names.

**Verify the columns first.** Microsoft documents the entity name but not its columns. Run this and confirm `Name`, `ClassGuid`, `DeviceID`, and `ConfigManagerErrorCode` appear before using the queries below:

```kusto
PNPDEVICEDRIVER | take 5
```

All devices in the Imaging class (scanners, plus some cameras):

```kusto
PNPDEVICEDRIVER | where ClassGuid == '{6bdd1fc6-810f-11d0-bec7-08002be2092f}'
```

Only the four brands:

```kusto
PNPDEVICEDRIVER | where ClassGuid == '{6bdd1fc6-810f-11d0-bec7-08002be2092f}' | where Name like '%canon%' or Name like '%lexmark%' or Name like '%ricoh%' or Name like '%fujitsu%' or Name like '%scansnap%' or Name startswith 'fi-' or DeviceID like '%VID_04C5%' or DeviceID like '%VID_04A9%' or DeviceID like '%VID_1083%' or DeviceID like '%VID_043D%' or DeviceID like '%VID_05CA%'
```

Scanners with no driver installed (they are not in the Imaging class yet):

```kusto
PNPDEVICEDRIVER | where ConfigManagerErrorCode == 28 | where Name like '%canon%' or Name like '%lexmark%' or Name like '%ricoh%' or Name like '%fujitsu%' or Name like '%scansnap%' or Name startswith 'fi-' or DeviceID like '%VID_04C5%' or DeviceID like '%VID_1083%'
```

Count of devices per model:

```kusto
PNPDEVICEDRIVER | where ClassGuid == '{6bdd1fc6-810f-11d0-bec7-08002be2092f}' | summarize dcount( Device ) by Name
```

Notes:

- `==` and `like` are case-insensitive in CMPivot, so GUID and name casing do not matter.
- Hardware-inventory entities return cached data from the last inventory cycle for offline clients (lighter text) and live data for online clients. Cached rows exist only if the *PNP Device Driver* class is enabled in your hardware inventory client settings.
- CMPivot cannot return array properties, so `HardwareID` is unavailable. The USB vendor ID is matched in `DeviceID` instead.
- These queries do not exclude webcams or check that a device is currently present. When that matters, use the Run Script.
- If a query errors on a column name, that column is not exposed in your site version. Remove that clause, or use the Run Script.

## Collections

[`../Collections/New-ScannerCollections.ps1`](../Collections/New-ScannerCollections.ps1) builds a "Scanners: All" collection and one collection per model from hardware inventory. It works with the default *PNP Device Driver* properties (Name, Device ID). Enabling **Class Guid** on that class in client settings makes it, and cached CMPivot results, cover every brand.

## References

Microsoft Learn:

- [Win32_PnPEntity class](https://learn.microsoft.com/windows/win32/cimwin32prov/win32-pnpentity)
- [System-defined device setup classes](https://learn.microsoft.com/windows-hardware/drivers/install/system-defined-device-setup-classes-available-to-vendors) (Imaging Device GUID)
- [Create and run PowerShell scripts from the Configuration Manager console](https://learn.microsoft.com/mem/configmgr/apps/deploy-use/create-deploy-scripts) (SYSTEM context, JSON output, 4 KB limit, logs)
- [CMPivot overview](https://learn.microsoft.com/mem/configmgr/core/servers/manage/cmpivot-overview) (entities, operators)
- [Changes to CMPivot](https://learn.microsoft.com/mem/configmgr/core/servers/manage/cmpivot-changes) (hardware-inventory entities, cached data, array limitation)

Not from Microsoft: USB vendor IDs are from the public USB-IF list (04C5 Fujitsu, 04A9 Canon, 1083 Canon Electronics, 043D Lexmark, 05CA Ricoh).
