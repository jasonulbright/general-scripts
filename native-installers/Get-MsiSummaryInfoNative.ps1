<#
.SYNOPSIS
    Reads the MSI Summary Information stream using the native Windows
    Installer COM API.

.DESCRIPTION
    The Summary Information stream is a standard OLE structured-storage
    block on every MSI / MSP and carries Title, Subject, Author, Keywords,
    Comments, the template string (which encodes target architecture and
    language), the package code, page count, word count, and revision
    number. Uses the documented WindowsInstaller.Installer ComObject.

    Native code only:
      - WindowsInstaller.Installer ComObject  (msi.dll, native Windows)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to a .msi or .msp file.

.EXAMPLE
    .\Get-MsiSummaryInfoNative.ps1 -Path .\setup.msi
#>
param([Parameter(Mandatory)][string]$Path)

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}
$resolved = (Resolve-Path -LiteralPath $Path).Path

# Summary Information property IDs (msiquery.h)
$pids = [ordered]@{
    Title       = 2
    Subject     = 3
    Author      = 4
    Keywords    = 5
    Comments    = 6
    Template    = 7
    LastAuthor  = 8
    RevNumber   = 9
    LastPrinted = 11
    CreateTime  = 12
    LastSaveTime= 13
    PageCount   = 14
    WordCount   = 15
    CharCount   = 16
    AppName     = 18
    Security    = 19
}

$installer = $null; $summary = $null
try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    # SummaryInformation(<path>, <updateCount>); updateCount = 0 = read-only.
    $summary = $installer.GetType().InvokeMember(
        'SummaryInformation', 'GetProperty', $null, $installer, @($resolved, 0))

    $out = [ordered]@{}
    foreach ($name in $pids.Keys) {
        try {
            $out[$name] = $summary.GetType().InvokeMember(
                'Property', 'GetProperty', $null, $summary, @($pids[$name]))
        } catch {
            $out[$name] = $null
        }
    }
    return [PSCustomObject]$out
} finally {
    foreach ($o in @($summary, $installer)) {
        if ($null -ne $o -and [System.Runtime.InteropServices.Marshal]::IsComObject($o)) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($o)
        }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
