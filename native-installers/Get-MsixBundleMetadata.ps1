<#
.SYNOPSIS
    Reads identity + child-package metadata from a .msixbundle or .appxbundle.

.DESCRIPTION
    Bundle files are standard ZIP packages with an AppxBundleManifest.xml
    at AppxMetadata\AppxBundleManifest.xml. This script reads <Identity>
    and the <Packages><Package> children to return the bundle's identity
    plus the list of inner package entries (one per architecture or
    resource pack).

    For single MSIX/APPX, use Get-MsixMetadata.ps1 instead.

    Native code only:
      - System.IO.Compression.ZipFile  (.NET BCL)
      - [xml]                          (PowerShell native cast)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to the .msixbundle or .appxbundle file.

.EXAMPLE
    .\Get-MsixBundleMetadata.ps1 -Path .\Contoso.SampleApp.msixbundle
#>
param([Parameter(Mandatory)][string]$Path)

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path))
try {
    $entry = $zip.Entries |
        Where-Object { $_.FullName -eq 'AppxMetadata/AppxBundleManifest.xml' } |
        Select-Object -First 1
    if (-not $entry) { return $null }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }

    $identity = $xml.Bundle.Identity
    $packages = @()
    if ($xml.Bundle.Packages) {
        foreach ($pkg in $xml.Bundle.Packages.Package) {
            $packages += [PSCustomObject]@{
                Type         = [string]$pkg.Type
                Version      = [string]$pkg.Version
                Architecture = [string]$pkg.Architecture
                FileName     = [string]$pkg.FileName
                Size         = [string]$pkg.Size
                Offset       = [string]$pkg.Offset
                ResourceId   = [string]$pkg.ResourceId
            }
        }
    }

    [PSCustomObject]@{
        Name                  = [string]$identity.Name
        Publisher             = [string]$identity.Publisher
        Version               = [string]$identity.Version
        ProcessorArchitecture = [string]$identity.ProcessorArchitecture
        Packages              = $packages
    }
} finally {
    $zip.Dispose()
}
