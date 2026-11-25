# HyperV

Tools that look inside a Hyper-V virtual machine from the host, through PowerShell Direct.

## Contents

| File | Purpose |
|------|---------|
| `Watch-VMLog.ps1` | Tails a log file inside a VM. Polls every N seconds and colors ERROR lines red and WARNING lines yellow. |
| `Get-VMLogInventory.ps1` | Finds the running processes and the log files in common places inside a VM: `C:\`, `Windows\Temp`, the SMS logs and the user temp folder. |

## Requirements

- Run on the Hyper-V host, elevated.
- A guest that supports PowerShell Direct, and credentials for it.
