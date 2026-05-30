<#
.SYNOPSIS
    Reads MSP patch metadata using the native Windows Installer COM API.

.DESCRIPTION
    An MSP is a Windows Installer Patch file. Its Summary Information
    stream carries the patch identity (PackageCode in the RevNumber
    field, target product codes in the Template field), and its
    MsiPatchMetadata table carries the friendly DisplayName /
    DisplayVersion / Manufacturer / TargetProductName the patch was
    authored with. This script returns both blocks via
    WindowsInstaller.Installer.

    Native code only:
      - WindowsInstaller.Installer ComObject  (msi.dll, native Windows)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to a .msp file.

.EXAMPLE
    .\Get-MspMetadataNative.ps1 -Path .\AdobeReaderPatch.msp
#>
param([Parameter(Mandatory)][string]$Path)

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}
$resolved = (Resolve-Path -LiteralPath $Path).Path

$installer = $null; $summary = $null; $db = $null; $view = $null; $record = $null
try {
    $installer = New-Object -ComObject WindowsInstaller.Installer

    # Summary stream first (works without opening the database)
    $summary = $installer.GetType().InvokeMember(
        'SummaryInformation', 'GetProperty', $null, $installer, @($resolved, 0))
    $summaryOut = [ordered]@{}
    foreach ($p in @(
        @{Name='Title';Pid=2}, @{Name='Subject';Pid=3}, @{Name='Author';Pid=4},
        @{Name='Keywords';Pid=5}, @{Name='Comments';Pid=6}, @{Name='Template';Pid=7},
        @{Name='RevNumber';Pid=9}, @{Name='AppName';Pid=18}
    )) {
        try {
            $summaryOut[$p.Name] = $summary.GetType().InvokeMember(
                'Property', 'GetProperty', $null, $summary, @($p.Pid))
        } catch { $summaryOut[$p.Name] = $null }
    }

    # MsiPatchMetadata table (open patch as MSI-style database with mode 32 = MsiOpenDatabaseModePatchFile)
    $patchMeta = [ordered]@{}
    try {
        $db = $installer.GetType().InvokeMember(
            'OpenDatabase', 'InvokeMethod', $null, $installer, @($resolved, 32))
        $view = $db.GetType().InvokeMember(
            'OpenView', 'InvokeMethod', $null, $db,
            @('SELECT Property, Value FROM MsiPatchMetadata WHERE Company IS NULL'))
        [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
        while ($true) {
            $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
            if ($null -eq $record) { break }
            $name  = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 1)
            $value = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 2)
            $patchMeta[$name] = $value
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)
        }
    } catch {
        # MsiPatchMetadata is optional in some patches; leave block empty.
    }

    [PSCustomObject]@{
        SummaryInformation = [PSCustomObject]$summaryOut
        PatchMetadata      = $patchMeta
    }
} finally {
    foreach ($o in @($view, $db, $summary, $installer)) {
        if ($null -ne $o -and [System.Runtime.InteropServices.Marshal]::IsComObject($o)) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($o)
        }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
