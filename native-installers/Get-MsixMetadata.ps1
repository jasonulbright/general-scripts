<#
.SYNOPSIS
    Reads identity metadata from a single MSIX / APPX package.

.DESCRIPTION
    An MSIX/APPX is a standard ZIP package with an AppxManifest.xml at the
    archive root. This script reads <Identity>, <Properties>, and the
    optional <Applications><Application> child to return DisplayName,
    Publisher, Version, and ProcessorArchitecture.

    For bundle files (.msixbundle / .appxbundle), use
    Get-MsixBundleMetadata.ps1 instead.

    Native code only:
      - System.IO.Compression.ZipFile  (.NET BCL)
      - [xml]                          (PowerShell native cast)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to the .msix or .appx file.

.EXAMPLE
    .\Get-MsixMetadata.ps1 -Path .\Contoso.SampleApp.msix
#>
param([Parameter(Mandatory)][string]$Path)

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path))
try {
    $entry = $zip.Entries |
        Where-Object { $_.FullName -eq 'AppxManifest.xml' } |
        Select-Object -First 1
    if (-not $entry) { return $null }

    $reader = New-Object System.IO.StreamReader($entry.Open())
    try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }

    $identity   = $xml.Package.Identity
    $properties = $xml.Package.Properties
    $appNode    = $null
    if ($xml.Package.Applications) {
        $appNode = @($xml.Package.Applications.Application)[0]
    }

    [PSCustomObject]@{
        Name                  = [string]$identity.Name
        Publisher             = [string]$identity.Publisher
        Version               = [string]$identity.Version
        ProcessorArchitecture = [string]$identity.ProcessorArchitecture
        ResourceId            = [string]$identity.ResourceId
        DisplayName           = [string]$properties.DisplayName
        PublisherDisplayName  = [string]$properties.PublisherDisplayName
        Description           = [string]$properties.Description
        Logo                  = [string]$properties.Logo
        ApplicationId         = if ($appNode) { [string]$appNode.Id } else { $null }
        Executable            = if ($appNode) { [string]$appNode.Executable } else { $null }
    }
} finally {
    $zip.Dispose()
}
