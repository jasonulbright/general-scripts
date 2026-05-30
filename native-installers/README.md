# Native Installer Metadata Readers

Single-purpose PowerShell scripts that read deployment metadata from
Windows installer packages.

## Native-only guarantee

Every script in this directory uses **only**:

- PowerShell (Windows PowerShell 5.1 or PowerShell 7+).
- The .NET Base Class Library shipped with Windows
  (`System.IO`, `System.IO.Compression`, `System.Text`, `System.Xml`).
- Documented native Windows COM objects (`WindowsInstaller.Installer`,
  shipped with `msi.dll` since the 1990s).

No bundled DLLs. No vendored PowerShell modules. No third-party
binaries. No external tools (`7z.exe`, `dark.exe`, `msiexec` flags,
etc.) are required to run any script.

Each script is self-contained: drop it on a workstation, pass `-Path`,
get a `PSCustomObject` back. No installer, no profile, no module
manifest.

## Scope

These scripts **read** installer metadata. They do not:

- Decrypt protected payloads (including `.intunewin` AES content).
- Bypass product licensing, generate keys, or remove activation checks.
- Modify, repackage, or redistribute third-party installer content.
- Make network calls.

They are functionally equivalent to opening the file in an archive
manager and reading the manifest XML, or calling
`WindowsInstaller.Installer` from any administrative script.

Every script in this directory maps to a publicly documented precedent
on GitHub, almost always owned by the format's vendor (Microsoft, WiX
Toolset, NuGet team, PSADT team, Squirrel team) or by a long-standing
community project (MSEndpointMgr, Heath Stewart, electron-builder).
See [SOURCES.md](SOURCES.md) for the per-script precedent map.

## Scripts

| Script | Format | Reads | Mechanism |
|---|---|---|---|
| [Get-NuspecMetadata.ps1](Get-NuspecMetadata.ps1) | `.nupkg` (NuGet, Chocolatey) | `*.nuspec` | ZIP + XML |
| [Get-IntunewinMetadata.ps1](Get-IntunewinMetadata.ps1) | `.intunewin` (Intune Win32) | `IntuneWinPackage\Metadata\Detection.xml` | ZIP + XML |
| [Get-MsixMetadata.ps1](Get-MsixMetadata.ps1) | `.msix` / `.appx` | `AppxManifest.xml` | ZIP + XML |
| [Get-MsixBundleMetadata.ps1](Get-MsixBundleMetadata.ps1) | `.msixbundle` / `.appxbundle` | `AppxMetadata\AppxBundleManifest.xml` | ZIP + XML |
| [Get-PsadtMetadata.ps1](Get-PsadtMetadata.ps1) | PSAppDeployToolkit v3 / v4 zip | `Deploy-Application.ps1` / `Invoke-AppDeployToolkit.ps1` | ZIP + regex |
| [Get-SquirrelMetadata.ps1](Get-SquirrelMetadata.ps1) | Squirrel.Windows / Electron-Squirrel `.exe` | first 32 KiB marker scan | byte read |
| [Get-MsiPropertiesNative.ps1](Get-MsiPropertiesNative.ps1) | `.msi` | Property table | `WindowsInstaller.Installer` COM |
| [Get-MsiSummaryInfoNative.ps1](Get-MsiSummaryInfoNative.ps1) | `.msi` / `.msp` | Summary Information stream | `WindowsInstaller.Installer` COM |
| [Get-MspMetadataNative.ps1](Get-MspMetadataNative.ps1) | `.msp` (Windows Installer Patch) | Summary Information + `MsiPatchMetadata` | `WindowsInstaller.Installer` COM |
| [Get-WixBurnMetadata.ps1](Get-WixBurnMetadata.ps1) | WiX Burn bundle `.exe` | `.wixburn` PE section `BURN_SECTION` header | `System.IO.BinaryReader` |

## Usage

```powershell
.\Get-MsiPropertiesNative.ps1 -Path .\setup.msi
.\Get-IntunewinMetadata.ps1   -Path .\App.intunewin
.\Get-MsixMetadata.ps1        -Path .\Contoso.SampleApp.msix
.\Get-WixBurnMetadata.ps1     -Path .\ContosoBundle.exe
```

Each script returns a `PSCustomObject` (or `$null` if the input does
not match the expected format). Pipe to `ConvertTo-Json` for a
machine-readable view:

```powershell
.\Get-NuspecMetadata.ps1 -Path .\sample.nupkg | ConvertTo-Json -Depth 4
```

## License

Inherits the MIT license of the parent `general-scripts` repository.
