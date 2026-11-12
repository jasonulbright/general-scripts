<#
.SYNOPSIS
    Inventories scanners currently connected to a Windows device. Built for
    the ConfigMgr "Run Scripts" feature (runs as SYSTEM, read-only).

.DESCRIPTION
    Reads Win32_PnPEntity (root\cimv2) and reports:

      1. Every present device in the Imaging device setup class
         {6bdd1fc6-810f-11d0-bec7-08002be2092f} ("still-image capture
         devices, digital cameras, and scanners"). Webcams that sit in that
         class (Service = usbvideo) are skipped.
      2. Present devices with NO driver installed (ConfigManagerErrorCode 28)
         that identify as Canon / Lexmark / Ricoh / Fujitsu by name or USB
         vendor ID. These show Match = "NoDriver" so they are easy to
         separate; a driverless scanner never lands in the Imaging class, so
         rule 1 alone would miss it.

    Each device is tagged with a Vendor (Fujitsu, Canon, Lexmark, Ricoh, or
    Other). Set $KnownVendorsOnly = $true below to drop "Other".

    OUTPUT (one string, so ConfigMgr can group identical results):
      - "No scanners found"            nothing matched
      - Compact JSON array             one object per scanner
      - "ERROR: <message>" + exit 1    the WMI query or script failed

    JSON fields:
      Vendor   Fujitsu | Canon | Lexmark | Ricoh | Other
      Model    Device name as shown in Device Manager
      Mfr      Manufacturer string from the driver
      Match    Image (Imaging class) | NoDriver (driver missing)
      Bus      First segment of the device ID: USB, SWD (WSD/network), ...
      VidPid   USB vendor:product ID, e.g. 04C5:114F (blank if not USB)
      Serial   USB serial number when the device reports one (blank if not)
      Status   WMI status, normally OK or Error
      Err      Device Manager problem code (0 = working, 28 = no driver)
      Service  Driver service name, e.g. usbscan, WSDScan
      Id       PnP device ID (unique key for de-duplication)

    ConfigMgr truncates script output at 4 KB. The script stops adding rows
    before that limit and appends {"Truncated":"<n> more not shown"} so a
    cut-off result is always visible and the JSON stays valid.

.NOTES
    Limits worth knowing before trusting a "No scanners found":
      - Only devices connected AND powered on at run time are reported
        (Present = True). Sheet-fed scanners that auto power off drop off the
        USB bus. Run during working hours and re-run to catch stragglers.
      - Network MFPs appear only if Windows installed them as a WSD scan
        device. Vendor network-TWAIN drivers and scan-to-email/folder create
        no PnP device on the workstation and cannot be seen from here.
      - Ricoh now owns the fi-series/ScanSnap line (formerly Fujitsu/PFU).
        Anything named fi-xxxx or ScanSnap is tagged Fujitsu regardless of
        the brand on the label.
      - USB vendor IDs come from the public USB-IF vendor list, not from
        Microsoft documentation: 04C5 Fujitsu, 04A9 Canon, 1083 Canon
        Electronics (DR-series), 043D Lexmark, 05CA Ricoh.

    Requires: Windows PowerShell 3.0+ (uses Get-CimInstance). No parameters,
    no network access, changes nothing on the device.

    References (Microsoft Learn):
      Win32_PnPEntity class
        https://learn.microsoft.com/windows/win32/cimwin32prov/win32-pnpentity
      System-defined device setup classes (Imaging Device GUID)
        https://learn.microsoft.com/windows-hardware/drivers/install/system-defined-device-setup-classes-available-to-vendors
      Create and run PowerShell scripts from the ConfigMgr console (4 KB / JSON)
        https://learn.microsoft.com/mem/configmgr/apps/deploy-use/create-deploy-scripts

.EXAMPLE
    .\Get-ConnectedScanners.ps1

    Local test from an elevated or standard prompt. Pipe to ConvertFrom-Json
    to read it as a table:  .\Get-ConnectedScanners.ps1 | ConvertFrom-Json | ft
#>

# ----------------------------------------------------------------------------
# Settings (edit here; Run Scripts parameters are deliberately not used)
# ----------------------------------------------------------------------------

# $false = report every scanner-class device, tagging unknown brands "Other".
# $true  = report only Fujitsu / Canon / Lexmark / Ricoh.
$KnownVendorsOnly = $false

# Stay under ConfigMgr's 4 KB output truncation.
$MaxOutputChars = 3800

# Imaging device setup class: still-image devices, cameras, scanners.
$ImageClassGuid = '{6bdd1fc6-810f-11d0-bec7-08002be2092f}'

# Checked top to bottom; first hit wins. Text is a case-insensitive regex run
# against manufacturer + device name. Vid is a regex of USB vendor IDs.
$VendorRules = @(
    @{ Vendor = 'Fujitsu'; Text = 'fujitsu|\bpfu\b|\bfi-\d|scansnap|paperstream'; Vid = '04C5' }
    @{ Vendor = 'Canon';   Text = 'canon';                                        Vid = '04A9|1083' }
    @{ Vendor = 'Lexmark'; Text = 'lexmark';                                      Vid = '043D' }
    @{ Vendor = 'Ricoh';   Text = 'ricoh';                                        Vid = '05CA' }
)

# ----------------------------------------------------------------------------

function ConvertTo-CleanText {
    # Printable ASCII only, trimmed, capped. Keeps the JSON small and safe.
    param([object]$Value, [int]$MaxLength = 60)
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value) -replace '[^\x20-\x7E]', ''
    $text = $text.Trim()
    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength) }
    return $text
}

try {
    $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)

    $rows = New-Object System.Collections.ArrayList

    foreach ($device in $devices) {

        # Present is $null on Windows 8.1 / Server 2012 R2 and older; only an
        # explicit $false means "known to Windows but not connected now".
        if ($device.Present -eq $false) { continue }

        $classGuid = [string]$device.ClassGuid
        $isImage   = ($classGuid -eq $ImageClassGuid)
        $noDriver  = ((-not $isImage) -and ($device.ConfigManagerErrorCode -eq 28))

        if ((-not $isImage) -and (-not $noDriver)) { continue }

        # Webcams on older drivers still register in the Imaging class.
        if ($isImage -and ([string]$device.Service -eq 'usbvideo')) { continue }

        $deviceId    = [string]$device.DeviceID
        $hardwareIds = (@($device.HardwareID) -join ' ')
        $nameText    = '{0} {1} {2} {3}' -f $device.Manufacturer, $device.Caption, $device.Name, $device.Description
        $idText      = '{0} {1}' -f $deviceId, $hardwareIds

        $vendor = 'Other'
        foreach ($rule in $VendorRules) {
            $vidPattern = 'VID_(' + $rule.Vid + ')(?![0-9A-F])'
            if (($nameText -match $rule.Text) -or ($idText -match $vidPattern)) {
                $vendor = $rule.Vendor
                break
            }
        }

        # A driverless device is only reported when it is one of our brands;
        # otherwise every unknown device on the fleet would be listed.
        if ($noDriver -and ($vendor -eq 'Other')) { continue }
        if ($KnownVendorsOnly -and ($vendor -eq 'Other')) { continue }

        $vidPid = ''
        if ($idText -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
            $vidPid = ('{0}:{1}' -f $Matches[1], $Matches[2]).ToUpper()
        }

        # USB\VID_xxxx&PID_xxxx\<serial>. If the last segment contains "&"
        # Windows generated it from the port and it is not a real serial.
        $bus    = ''
        $serial = ''
        $idParts = $deviceId.Split('\')
        if ($idParts.Count -ge 1) { $bus = $idParts[0] }
        if (($idParts.Count -ge 3) -and ($bus -eq 'USB') -and ($idParts[2] -notmatch '&')) {
            $serial = $idParts[2]
        }

        $model = $device.Caption
        if ([string]::IsNullOrEmpty([string]$model)) { $model = $device.Name }

        $match = 'Image'
        if ($noDriver) { $match = 'NoDriver' }

        $errorCode = 0
        if ($null -ne $device.ConfigManagerErrorCode) { $errorCode = [int]$device.ConfigManagerErrorCode }

        $row = [pscustomobject][ordered]@{
            Vendor  = $vendor
            Model   = ConvertTo-CleanText $model 64
            Mfr     = ConvertTo-CleanText $device.Manufacturer 40
            Match   = $match
            Bus     = ConvertTo-CleanText $bus 20
            VidPid  = $vidPid
            Serial  = ConvertTo-CleanText $serial 40
            Status  = ConvertTo-CleanText $device.Status 12
            Err     = $errorCode
            Service = ConvertTo-CleanText $device.Service 24
            Id      = ConvertTo-CleanText $deviceId 120
        }
        [void]$rows.Add($row)
    }

    if ($rows.Count -eq 0) {
        Write-Output 'No scanners found'
        exit 0
    }

    # Known brands first, then by model, so truncation drops "Other" first.
    $sorted = @($rows | Sort-Object -Property @{ Expression = { if ($_.Vendor -eq 'Other') { 1 } else { 0 } } }, Vendor, Model, Id)

    # Serialise one object at a time and join by hand. This sidesteps the
    # Windows PowerShell 5.1 quirks around arrays in ConvertTo-Json and lets
    # the script stop cleanly before the 4 KB limit.
    $parts  = New-Object System.Collections.ArrayList
    $length = 2   # the surrounding [ ]
    $shown  = 0
    foreach ($row in $sorted) {
        $json = ConvertTo-Json -InputObject $row -Compress -Depth 2
        if (($length + $json.Length + 1) -gt ($MaxOutputChars - 40)) { break }
        [void]$parts.Add($json)
        $length += $json.Length + 1
        $shown++
    }

    $hidden = $sorted.Count - $shown
    if ($hidden -gt 0) {
        [void]$parts.Add('{"Truncated":"' + $hidden + ' more not shown"}')
    }

    Write-Output ('[' + ($parts -join ',') + ']')
    exit 0
}
catch {
    $message = ConvertTo-CleanText $_.Exception.Message 300
    Write-Output ('ERROR: ' + $message)
    exit 1
}
