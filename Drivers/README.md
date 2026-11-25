# Drivers

Tools for the Windows driver store.

## Contents

| File | Purpose |
|------|---------|
| `Remove-DriverStoreEntries.ps1` | Removes stubborn drivers from the driver store by regex pattern. It force-removes with `pnputil` and deletes the `FileRepository` folders with `takeown` and `icacls`. The default pattern targets the Alienware Command Center (AWCC) reinstall loop. Supports `-WhatIf`. |

## Requirements

- Run elevated. The script changes system files.
- Use `-WhatIf` first. A removed driver package is not recoverable from the script.
