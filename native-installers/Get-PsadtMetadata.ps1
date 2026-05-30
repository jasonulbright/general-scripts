<#
.SYNOPSIS
    Detects PSAppDeployToolkit v3 / v4 layout inside a zip and reads the
    deployment script's identity fields.

.DESCRIPTION
    PSADT packages are typically distributed as zip archives. v3 contains
    Deploy-Application.exe + Deploy-Application.ps1; v4 contains
    Invoke-AppDeployToolkit.exe + Invoke-AppDeployToolkit.ps1. This script
    detects which variant is present by sentinel filename, then reads the
    deployment script body to extract the standard AppVendor / AppName /
    AppVersion / AppArch / AppLang / AppRevision variables that PSADT
    requires every wrapper to set near the top of the script.

    Native code only:
      - System.IO.Compression.ZipFile  (.NET BCL)
      - Regex pattern matching         (PowerShell native)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to a .zip archive containing a PSADT layout.

.EXAMPLE
    .\Get-PsadtMetadata.ps1 -Path .\7-Zip-PSADT-v4.zip
#>
param([Parameter(Mandatory)][string]$Path)

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

function Read-ZipEntryText {
    param([System.IO.Compression.ZipArchive]$Zip, [string]$Name)
    $entry = $Zip.Entries | Where-Object { $_.FullName -eq $Name } | Select-Object -First 1
    if (-not $entry) { return $null }
    $r = New-Object System.IO.StreamReader($entry.Open())
    try { return $r.ReadToEnd() } finally { $r.Dispose() }
}

$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path))
try {
    $entries = $zip.Entries | ForEach-Object { $_.FullName }

    $v4Sentinel = $entries -contains 'Invoke-AppDeployToolkit.ps1' -or
                  $entries -contains 'Invoke-AppDeployToolkit.exe'
    $v3Sentinel = $entries -contains 'Deploy-Application.ps1' -or
                  $entries -contains 'Deploy-Application.exe'

    $variant  = $null
    $scriptName = $null
    if ($v4Sentinel) {
        $variant    = 'PsadtV4'
        $scriptName = 'Invoke-AppDeployToolkit.ps1'
    } elseif ($v3Sentinel) {
        $variant    = 'PsadtV3'
        $scriptName = 'Deploy-Application.ps1'
    } else {
        return $null
    }

    $script = Read-ZipEntryText -Zip $zip -Name $scriptName
    if (-not $script) {
        return [PSCustomObject]@{ Variant = $variant; ScriptPresent = $false }
    }

    function Get-Field {
        param([string]$Body, [string]$Name)
        $pattern = '(?im)^\s*\[(?:[A-Za-z\.]+)\]\s*\$' + [regex]::Escape($Name) + "\s*=\s*'([^']*)'"
        $m = [regex]::Match($Body, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
        $altPattern = '(?im)^\s*\$' + [regex]::Escape($Name) + "\s*=\s*'([^']*)'"
        $m = [regex]::Match($Body, $altPattern)
        if ($m.Success) { return $m.Groups[1].Value }
        return $null
    }

    [PSCustomObject]@{
        Variant       = $variant
        ScriptPresent = $true
        AppVendor     = Get-Field -Body $script -Name 'appVendor'
        AppName       = Get-Field -Body $script -Name 'appName'
        AppVersion    = Get-Field -Body $script -Name 'appVersion'
        AppArch       = Get-Field -Body $script -Name 'appArch'
        AppLang       = Get-Field -Body $script -Name 'appLang'
        AppRevision   = Get-Field -Body $script -Name 'appRevision'
    }
} finally {
    $zip.Dispose()
}
