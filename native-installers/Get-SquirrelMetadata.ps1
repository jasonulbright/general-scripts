<#
.SYNOPSIS
    Detects Squirrel.Windows / Electron-Squirrel installer markers in an EXE.

.DESCRIPTION
    Squirrel installers embed a small set of well-known marker strings
    early in the PE image: 'Squirrel', 'SquirrelTemp', 'Update.exe', and
    references to a RELEASES file. This script reads the first 32 KiB of
    the input EXE and scans both ASCII and UTF-16LE forms for these
    markers, returning a PSCustomObject describing what was found.

    The marker scan is conservative (presence-only); confirming a binary
    is "definitely Squirrel" requires looking at the actual update
    metadata, which Squirrel-managed apps emit at install time under
    %LocalAppData%.

    Native code only:
      - System.IO.File / BinaryReader  (.NET BCL)
      - System.Text.Encoding           (.NET BCL)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to the candidate EXE.

.EXAMPLE
    .\Get-SquirrelMetadata.ps1 -Path .\ContosoApp-Setup.exe
#>
param([Parameter(Mandatory)][string]$Path)

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$scanLength = [Math]::Min($bytes.Length, 32768)
$scan = New-Object byte[] $scanLength
[Array]::Copy($bytes, $scan, $scanLength)

$ascii = [System.Text.Encoding]::ASCII.GetString($scan)
$utf16 = [System.Text.Encoding]::Unicode.GetString($scan)

$markers = @(
    'Squirrel'
    'SquirrelTemp'
    'SquirrelSetup'
    'Update.exe'
    'RELEASES'
    'squirrel-install'
)

$found = @{}
foreach ($m in $markers) {
    $found[$m] = ($ascii.IndexOf($m) -ge 0) -or ($utf16.IndexOf($m) -ge 0)
}

$isSquirrel = $found['Squirrel'] -or $found['SquirrelTemp'] -or $found['SquirrelSetup']

[PSCustomObject]@{
    IsSquirrelInstaller = [bool]$isSquirrel
    HasUpdateExe        = [bool]$found['Update.exe']
    HasReleasesMarker   = [bool]$found['RELEASES']
    ScannedBytes        = $scanLength
    Markers             = $found
}
