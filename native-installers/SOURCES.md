# Sources and Public Precedents

Every script in this directory implements a capability that is already
publicly documented or implemented on GitHub by the format's vendor or
by a long-standing community project. Nothing here is novel
reverse-engineering; the scripts compose well-known reads behind a
common shape (`Get-*` PowerShell scripts that return `PSCustomObject`).

The table below maps each script to its public precedent. Each
precedent was verified directly against the linked repository.

## Per-script precedent map

| Script | Capability | Public precedent (GitHub) | Precedent license | Authority |
|---|---|---|---|---|
| [Get-NuspecMetadata.ps1](Get-NuspecMetadata.ps1) | Read `.nuspec` from a `.nupkg` ZIP | [NuGet/NuGet.Client](https://github.com/NuGet/NuGet.Client) — official .NET Foundation client | Apache 2.0 | Vendor (NuGet team / .NET Foundation) |
| [Get-NuspecMetadata.ps1](Get-NuspecMetadata.ps1) | Same (Chocolatey side) | [chocolatey/choco](https://github.com/chocolatey/choco) — official Chocolatey CLI | Apache 2.0 | Vendor (Chocolatey team) |
| [Get-IntunewinMetadata.ps1](Get-IntunewinMetadata.ps1) | Parse `IntuneWinPackage/Metadata/Detection.xml` from a `.intunewin` ZIP | [MSEndpointMgr/IntuneWin32App](https://github.com/MSEndpointMgr/IntuneWin32App) — `Expand-IntuneWin32AppPackage` explicitly reads Detection.xml for `EncryptionKey` and `InitializationVector` | MIT | Community standard (MSEndpointMgr) |
| [Get-IntunewinMetadata.ps1](Get-IntunewinMetadata.ps1) | Same (long-standing community decoder) | [okieselbach/Intune](https://github.com/okieselbach/Intune/tree/master/IntuneWinAppUtilDecoder) — `IntuneWinAppUtilDecoder` (Oliver Kieselbach) | See repo | Community standard (referenced by MSEndpointMgr blog) |
| [Get-IntunewinMetadata.ps1](Get-IntunewinMetadata.ps1) | Format authority (create side) | [microsoft/Microsoft-Win32-Content-Prep-Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) — the tool that creates `.intunewin` files | Microsoft proprietary (not OSS) | Vendor (Microsoft Intune team) |
| [Get-MsixMetadata.ps1](Get-MsixMetadata.ps1) | Read `AppxManifest.xml` from a `.msix` / `.appx` ZIP | [microsoft/msix-packaging](https://github.com/microsoft/msix-packaging) — official MSIX SDK, create + extract | MIT | Vendor (Microsoft App Platform) |
| [Get-MsixBundleMetadata.ps1](Get-MsixBundleMetadata.ps1) | Read `AppxBundleManifest.xml` from a `.msixbundle` / `.appxbundle` ZIP | [microsoft/msix-packaging](https://github.com/microsoft/msix-packaging) | MIT | Vendor (Microsoft) |
| [Get-PsadtMetadata.ps1](Get-PsadtMetadata.ps1) | Detect v3 / v4 sentinel files (`Deploy-Application.ps1` / `Invoke-AppDeployToolkit.ps1`) and read `appVendor` / `appName` / `appVersion` / `appArch` / `appLang` / `appRevision` | [PSAppDeployToolkit/PSAppDeployToolkit](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit) — official toolkit, documents both sentinel filenames and the variable contract | LGPL | Vendor (PSADT team) |
| [Get-SquirrelMetadata.ps1](Get-SquirrelMetadata.ps1) | Scan EXE for `Squirrel`, `SquirrelTemp`, `Update.exe`, `RELEASES` markers | [Squirrel/Squirrel.Windows](https://github.com/Squirrel/Squirrel.Windows) — official Squirrel framework that emits those markers | MIT | Vendor (Squirrel team) |
| [Get-SquirrelMetadata.ps1](Get-SquirrelMetadata.ps1) | Same (alternate emitter) | [electron-userland/electron-builder](https://github.com/electron-userland/electron-builder) — produces Squirrel.Windows installers | MIT | Community standard (electron-builder team) |
| [Get-MsiPropertiesNative.ps1](Get-MsiPropertiesNative.ps1) | `SELECT Property, Value FROM Property` via `WindowsInstaller.Installer` COM | [heaths/psmsi](https://github.com/heaths/psmsi) — canonical PowerShell MSI module by Heath Stewart (Microsoft engineer), on the PowerShell Gallery | MIT | Canonical reference (Microsoft engineer's personal MIT-licensed project) |
| [Get-MsiPropertiesNative.ps1](Get-MsiPropertiesNative.ps1) | Same capability via the DTF library | [wixtoolset/wix](https://github.com/wixtoolset/wix) — `Microsoft.Deployment.WindowsInstaller` (DTF) is the canonical .NET wrapper around the same COM API | MS-RL | Vendor (WiX Toolset team) |
| [Get-MsiSummaryInfoNative.ps1](Get-MsiSummaryInfoNative.ps1) | Read MSI Summary Information stream via the same COM | [heaths/psmsi](https://github.com/heaths/psmsi) | MIT | Canonical reference |
| [Get-MspMetadataNative.ps1](Get-MspMetadataNative.ps1) | Read MSP `SummaryInformation` + `MsiPatchMetadata` table via the same COM | [heaths/psmsi](https://github.com/heaths/psmsi) | MIT | Canonical reference |
| [Get-WixBurnMetadata.ps1](Get-WixBurnMetadata.ps1) | Parse the `.wixburn` PE section's `BURN_SECTION` header to extract the BundleId GUID | [wixtoolset/wix](https://github.com/wixtoolset/wix/blob/main/src/burn/stub/StubSection.cpp) — `StubSection.cpp` declares the `BURN_SECTION_NAME` PE section via `#pragma section`; full `BURN_SECTION` struct lives in the burn engine headers in the same repo | MS-RL | Vendor (WiX Toolset team) |
| [Get-WixBurnMetadata.ps1](Get-WixBurnMetadata.ps1) | PE / COFF header parsing in .NET | [dotnet/runtime](https://github.com/dotnet/runtime) — `System.Reflection.PortableExecutable` namespace ships `PEReader` in the .NET BCL | MIT | Vendor (.NET Foundation) |

## License diversity across precedents

The precedents above span Apache 2.0, MIT, LGPL, and Microsoft Reciprocal
License (MS-RL). All four are OSI-approved licenses. The scripts in this
directory are pure-PowerShell re-implementations of capabilities those
projects already publish; they vendor no source from any of them.

## What this directory does NOT do

- Does not bypass product licensing.
- Does not generate, recover, or distribute license keys.
- Does not remove or bypass activation checks.
- Does not decrypt protected payloads (the `.intunewin` AES content
  remains encrypted; only the unencrypted `Detection.xml` is read, and
  key-shaped fields are redacted by default).
- Does not redistribute third-party installer content.
- Does not make network calls.

For the broader native-only guarantee (PowerShell + .NET BCL + native
Windows COM, no bundled binaries, no third-party modules, no external
tools), see [README.md](README.md).
