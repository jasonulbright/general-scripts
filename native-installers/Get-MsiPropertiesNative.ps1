<#
.SYNOPSIS
    Reads every row of an MSI Property table using the native Windows
    Installer COM API.

.DESCRIPTION
    Uses the documented WindowsInstaller.Installer ComObject (msi.dll,
    shipped with every supported Windows version since the 1990s) to
    open the database read-only and execute 'SELECT Property, Value FROM
    Property'. Returns an ordered hashtable of every Property row.

    This script intentionally avoids the PSGallery 'MSI' module so that
    no third-party PowerShell module is required.

    Native code only:
      - WindowsInstaller.Installer ComObject  (msi.dll, native Windows)
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to a .msi file.

.EXAMPLE
    .\Get-MsiPropertiesNative.ps1 -Path .\setup.msi
#>
param([Parameter(Mandatory)][string]$Path)

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}
$resolved = (Resolve-Path -LiteralPath $Path).Path

$installer = $null; $db = $null; $view = $null; $record = $null
try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember(
        'OpenDatabase', 'InvokeMethod', $null, $installer, @($resolved, 0))
    $view = $db.GetType().InvokeMember(
        'OpenView', 'InvokeMethod', $null, $db, @('SELECT Property, Value FROM Property'))
    [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)

    $result = [ordered]@{}
    while ($true) {
        $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if ($null -eq $record) { break }
        $name  = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 1)
        $value = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 2)
        $result[$name] = $value
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)
    }
    return $result
} finally {
    foreach ($o in @($view, $db, $installer)) {
        if ($null -ne $o -and [System.Runtime.InteropServices.Marshal]::IsComObject($o)) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($o)
        }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
