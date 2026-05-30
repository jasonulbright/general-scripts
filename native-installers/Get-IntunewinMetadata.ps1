<#
.SYNOPSIS
    Reads the unencrypted Detection.xml metadata from a .intunewin package.

.DESCRIPTION
    A .intunewin is a standard ZIP package produced by Microsoft's Win32
    Content Prep Tool. The unencrypted ApplicationInfo/Detection.xml lives
    at IntuneWinPackage\Metadata\Detection.xml. The inner content payload
    is AES-encrypted; this script does NOT attempt decryption.

    AES key material (EncryptionKey, MacKey, IV, Mac) is redacted by
    default. Pass -IncludeKeyMaterial to surface the raw values; the
    digest and profile-identifier fields are always surfaced.

    Native code only:
      - System.IO.Compression.ZipFile  (.NET BCL)
      - [xml]                          (PowerShell native cast)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to the .intunewin file.

.PARAMETER IncludeKeyMaterial
    Surface raw AES key fields verbatim instead of '<redacted>'.

.EXAMPLE
    .\Get-IntunewinMetadata.ps1 -Path .\App.intunewin
#>
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$IncludeKeyMaterial
)

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path))
try {
    $entry = $zip.Entries |
        Where-Object { $_.FullName -eq 'IntuneWinPackage/Metadata/Detection.xml' } |
        Select-Object -First 1
    if (-not $entry) { return $null }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    [xml]$xml = $text

    $app = $xml.ApplicationInfo
    if (-not $app) { return $null }

    $enc = $app.EncryptionInfo
    $encOut = if ($enc) {
        if ($IncludeKeyMaterial) {
            [ordered]@{
                Encrypted            = $true
                EncryptionKey        = [string]$enc.EncryptionKey
                MacKey               = [string]$enc.MacKey
                InitializationVector = [string]$enc.InitializationVector
                Mac                  = [string]$enc.Mac
                ProfileIdentifier    = [string]$enc.ProfileIdentifier
                FileDigest           = [string]$enc.FileDigest
                FileDigestAlgorithm  = [string]$enc.FileDigestAlgorithm
            }
        } else {
            [ordered]@{
                Encrypted            = $true
                EncryptionKey        = '<redacted>'
                MacKey               = '<redacted>'
                InitializationVector = '<redacted>'
                Mac                  = '<redacted>'
                ProfileIdentifier    = [string]$enc.ProfileIdentifier
                FileDigest           = [string]$enc.FileDigest
                FileDigestAlgorithm  = [string]$enc.FileDigestAlgorithm
            }
        }
    } else { [ordered]@{} }

    $msi = $null
    if ($app.MsiInfo) {
        $mi = $app.MsiInfo
        $msi = [ordered]@{
            MsiProductCode      = [string]$mi.MsiProductCode
            MsiProductVersion   = [string]$mi.MsiProductVersion
            MsiUpgradeCode      = [string]$mi.MsiUpgradeCode
            MsiExecutionContext = [string]$mi.MsiExecutionContext
            MsiPublisher        = [string]$mi.MsiPublisher
        }
    }

    [PSCustomObject]@{
        ToolVersion            = [string]$app.ToolVersion
        Name                   = [string]$app.Name
        FileName               = [string]$app.FileName
        SetupFile              = [string]$app.SetupFile
        UnencryptedContentSize = [string]$app.UnencryptedContentSize
        IsMsiSource            = [bool]$msi
        MsiInfo                = $msi
        EncryptionInfo         = $encOut
    }
} finally {
    $zip.Dispose()
}
