# DotNet

Tools for .NET assemblies.

## Contents

| File | Purpose |
|------|---------|
| `Get-AssemblyInfo.ps1` | Inspects a .NET DLL with reflection. Lists every type in the assembly. For each type it lists the public instance properties and methods that the type declares (without property accessors), and the custom attributes. Use it when you decompile or retarget a vendored library. |

## Requirements

PowerShell 5.1 or later. The script loads the assembly that you name.
