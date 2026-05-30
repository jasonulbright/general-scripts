<#
.SYNOPSIS
    Reads the .nuspec metadata block from a .nupkg / NuGet / Chocolatey package.

.DESCRIPTION
    A .nupkg is a standard ZIP file with a single root-level .nuspec XML
    manifest. This script opens the archive, locates that manifest, parses
    its <package><metadata> element, and returns a PSCustomObject with the
    common identity fields.

    Native code only:
      - System.IO.Compression.ZipFile  (.NET BCL)
      - [xml]                          (PowerShell native cast)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to the .nupkg file.

.EXAMPLE
    .\Get-NuspecMetadata.ps1 -Path .\sample.1.2.3.nupkg
#>
param([Parameter(Mandatory)][string]$Path)

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path))
try {
    $nuspec = $zip.Entries |
        Where-Object { $_.FullName -like '*.nuspec' -and $_.FullName -notmatch '/' } |
        Select-Object -First 1
    if (-not $nuspec) { return $null }

    $reader = New-Object System.IO.StreamReader($nuspec.Open())
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }

    $m = $xml.package.metadata
    [PSCustomObject]@{
        Id          = [string]$m.id
        Version     = [string]$m.version
        Title       = [string]$m.title
        Authors     = [string]$m.authors
        Owners      = [string]$m.owners
        Description = [string]$m.description
        ProjectUrl  = [string]$m.projectUrl
        LicenseUrl  = [string]$m.licenseUrl
        IconUrl     = [string]$m.iconUrl
        Tags        = [string]$m.tags
    }
} finally {
    $zip.Dispose()
}
