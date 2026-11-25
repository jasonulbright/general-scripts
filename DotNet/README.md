# DotNet

Tools for .NET assemblies.

## Contents

| File | Purpose |
|------|---------|
| `Get-AssemblyInfo.ps1` | Inspects a .NET DLL with reflection. Lists the public types with their declared properties, methods (without property accessors), and custom attributes. Use it when you decompile or retarget a vendored library. |

## Requirements

PowerShell 5.1 or later. The script loads the assembly that you name.
