# Sign-ExcelMacros

WPF tool that signs the VBA projects inside Excel macro files with a code-signing certificate from the current user's certificate store. Drop files or folders onto the window (or use **Add files** / **Add folder**). Folders are searched recursively, files without a VBA project are skipped, and one button signs the rest.

Signing goes through `Set-AuthenticodeSignature`, which signs any file type that has a registered Subject Interface Package (SIP). Office files need Microsoft's Office SIP.

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | Windows PowerShell 5.1, or PowerShell 7 on Windows. Must run in STA (the default for both). |
| Office SIP | [Microsoft Office Subject Interface Packages for Digitally Signing VBA Projects](https://www.microsoft.com/download/details.aspx?id=56617), registered with `regsvr32` for the same bitness as the PowerShell process (x64 build for 64-bit PowerShell, x86 build for 32-bit). `msosipx.dll` covers .xlsm, .xlsb, .xltm, .xlam; `msosip.dll` covers .xls, .xlt, .xla. Office does not need to be installed. |
| Certificate | Code-signing certificate (Code Signing EKU) with its private key in `Cert:\CurrentUser\My`, or a .pfx to import. |
| Rights | Standard user. Registering the SIP needs administrator rights once. |

## Usage

```powershell
powershell.exe -NoProfile -STA -File .\Sign-ExcelMacros.ps1

# Internal timestamp server
powershell.exe -NoProfile -STA -File .\Sign-ExcelMacros.ps1 -TimestampServer 'http://timestamp.contoso.com'
```

On launch the tool looks in `Cert:\CurrentUser\My` for currently valid code-signing certificates with a private key:

| Found | Behavior |
|---|---|
| 0 | Offers to import a .pfx. The file is checked for a private key, the Code Signing EKU, and validity dates before anything is written to the store. |
| 1 | Used automatically. |
| 2 or more | Opens a certificate picker. |

**Change...** reopens the picker, including **Import .pfx...**, at any time.

The timestamp server defaults to `http://timestamp.digicert.com`. Clear the box to sign without a timestamp.

## Behavior

- Open XML files (.xlsm, .xlsb, .xltm, .xlam) count as macro files when the package contains `vbaProject.bin`; legacy files (.xls, .xlt, .xla) when the compound file contains a `_VBA_PROJECT_CUR` storage. Office owner files (`~$*`) are ignored.
- Status column: **Ready**, **Signed**, **Failed** (Details has the reason; hover for the full text), **Skipped** (no VBA project, or the file could not be read).
- **Sign** processes Ready and Failed rows, so a failed file can be retried after fixing the cause.
- Files are signed in place and must not be open in Excel.
- Excel files whose Office SIP is not registered for the running PowerShell process are marked Failed without being opened; the check looks for `msosipx.dll` / `msosip.dll` SIP registrations. `Set-AuthenticodeSignature` otherwise keeps a file with no registered SIP open until the process exits.
- A banner appears when the Office SIP is missing, partly registered, or registered only for the other bitness, with a download link or a restart into the matching Windows PowerShell.
- Drag-and-drop from Explorer does not reach an elevated window (Windows UIPI). The drop zone shows a warning when the tool runs as administrator.

## Trusting the signature on clients

Signed macros open enabled only where the signing certificate is a trusted publisher (and its chain is trusted). For the recommended **Disable all except digitally signed macros** plus **Require macros to be signed by a trusted publisher** policy, deploy the public certificate to **Trusted Publishers**:

- Group Policy: Computer Configuration > Policies > Windows Settings > Security Settings > Public Key Policies > Trusted Publishers
- Script: `certutil -addstore TrustedPublisher <signing-certificate>.cer`

Excel add-ins (.xla, .xlam) that carry Mark of the Web are not trusted through a signature; unblock the file or load it from a trusted location.

References: [Trusted publishers for Office files](https://learn.microsoft.com/microsoft-365-apps/security/trusted-publisher), [Macros from the internet are blocked by default in Office](https://learn.microsoft.com/microsoft-365-apps/security/internet-macros-blocked).

## Tests

```powershell
Invoke-Pester -Path .\Sign-ExcelMacros.Tests.ps1 -Output Detailed
```

Requires Pester 5. The tests load the script's functions without opening the window, sign a temporary file with a throwaway self-signed certificate whose key is deleted afterwards, and never write to a certificate store. Signing a real Office file is not covered because it needs the Office SIP.

## File Structure

```
Office/Sign-ExcelMacros/
    Sign-ExcelMacros.ps1          # WPF tool
    Sign-ExcelMacros.Tests.ps1    # Pester tests
    README.md                     # This file
```
