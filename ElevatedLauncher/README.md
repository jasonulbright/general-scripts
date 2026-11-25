# ElevatedLauncher

A small GUI for starting applications under alternate (elevated) credentials.

## Contents

| File | Purpose |
|------|---------|
| `ElevatedLauncher.ps1` | WinForms window that launches applications under alternate credentials. It stores the credentials encrypted with AES on disk and keeps your list of applications in a JSON file. |

## Requirements

PowerShell 5.1 or later on Windows. The credential files are on the local disk, so use the tool only on a computer that you control.
