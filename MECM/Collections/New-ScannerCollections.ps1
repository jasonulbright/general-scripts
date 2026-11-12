<#
.SYNOPSIS
    Discovers the scanner models present in hardware inventory and creates one
    MECM device collection per model, under a parent "Scanners: All" collection.

.DESCRIPTION
    Two modes, same script:

      -Discover   Read-only. Lists every distinct scanner device name found in
                  SMS_G_System_PNP_DEVICE_DRIVER with a device count, and
                  prints a ready-to-paste $ScannerModels block. Creates nothing.

      (default)   Creates the parent collection, then one query collection per
                  entry in the $ScannerModels table at the top of this script.
                  Collections that already exist are skipped, never modified,
                  so the script is safe to re-run after adding models.

    Workflow:
      1. Run with -Discover.
      2. Paste the printed block over $ScannerModels below. Merge variants of
         one model into one pattern (fi-6130, fi-6130dj, fi-6130Z -> 'fi-6130%')
         and delete anything that is not a scanner.
      3. Run without -Discover.

    What counts as a scanner (the parent collection and -Discover use the same
    filter, so what you discover is what the collection will contain):

      Default        Name / USB vendor ID match, using only the properties
                     enabled by default for "PNP Device Driver": Name, DeviceID.
                     Covers Fujitsu fi-series / ScanSnap (USB VID 04C5) and
                     Canon document scanners (USB VID 1083, CanoScan). Edit
                     $ScannerDeviceIdPatterns / $ScannerNamePatterns to extend.

      -UseClassGuid  ClassGuid = Imaging device class. Every brand, including
                     Lexmark / Ricoh / Canon MFP scan interfaces. REQUIRES the
                     "Class Guid" property to be enabled on PNP Device Driver
                     (Win32_PnpEntity) in hardware inventory client settings,
                     and one inventory cycle to have run since. Without that
                     the query fails or returns nothing.

    Model collections are limited to the parent collection and match on device
    name only:  Name like "<pattern>".

    Refresh: scheduled daily full evaluation, no incremental updates. Queries
    built on hardware inventory only gain or lose members during a scheduled
    update, and Microsoft recommends keeping incremental collections under
    about 200, so incremental would add load here for no benefit.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER LimitingCollectionName
    Limiting collection for the parent collection. Default: "All Systems".

.PARAMETER AllCollectionName
    Name of the parent collection. Default: "Scanners: All".

.PARAMETER UseClassGuid
    Identify scanners by the Imaging device class GUID instead of name and USB
    vendor ID. See the requirement in the description.

.PARAMETER Discover
    List scanner models found in inventory and exit. Creates nothing.

.EXAMPLE
    .\New-ScannerCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -Discover

.EXAMPLE
    .\New-ScannerCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -Discover |
        Export-Csv .\scanner-models.csv -NoTypeInformation

.EXAMPLE
    .\New-ScannerCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local

.EXAMPLE
    .\New-ScannerCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -UseClassGuid -LimitingCollectionName "All Windows Devices"

.NOTES
    Inventory is a snapshot: a scanner that was unplugged or powered off when
    hardware inventory ran is not in the data until a later cycle sees it.

    USB vendor IDs are from the public USB-IF list (04C5 Fujitsu, 1083 Canon
    Electronics). 04C5 also appears on Fujitsu-built PCs; if you have those,
    expect non-scanner names in -Discover and trim them.

    References (Microsoft Learn):
      New-CMDeviceCollection
        https://learn.microsoft.com/powershell/module/configurationmanager/new-cmdevicecollection
      Invoke-CMWmiQuery
        https://learn.microsoft.com/powershell/module/configurationmanager/invoke-cmwmiquery
      Best practices for collections (limit incremental updates)
        https://learn.microsoft.com/mem/configmgr/core/clients/manage/collections/best-practices-for-collections
      Collection evaluation (hardware-inventory queries, evaluation graph)
        https://learn.microsoft.com/mem/configmgr/core/clients/manage/collections/collection-evaluation
      WQL LIKE operator
        https://learn.microsoft.com/windows/win32/wmisdk/like-operator
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$LimitingCollectionName = 'All Systems',

    [string]$AllCollectionName = 'Scanners: All',

    [switch]$UseClassGuid,

    [switch]$Discover
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Scanner models: collection name = WQL LIKE pattern matched against the device
# name. % = any run of characters, _ = any single character.
# Empty on purpose. Fill it with the block printed by -Discover, e.g.
#     'Scanners: <Model>' = '<device name pattern>%'
# ============================================================================

$ScannerModels = [ordered]@{
}

# ============================================================================
# What identifies a scanner when -UseClassGuid is NOT set.
# WQL LIKE patterns. A backslash must be written twice.
# ============================================================================

$ScannerDeviceIdPatterns = @(
    'USB\\VID_04C5&PID%'    # Fujitsu / PFU (fi-series, ScanSnap)
    'USB\\VID_1083&PID%'    # Canon Electronics (DR-, CR-series)
)

$ScannerNamePatterns = @(
    'fi-%'
    '%ScanSnap%'
    '%CanoScan%'
)

# Imaging device setup class: still-image devices, cameras, scanners.
$ImageClassGuid = '{6bdd1fc6-810f-11d0-bec7-08002be2092f}'

# ============================================================================
# Build WQL
# ============================================================================

$PnpClass = 'SMS_G_System_PNP_DEVICE_DRIVER'

if ($UseClassGuid) {
    $ScannerFilter = '{0}.ClassGuid = "{1}"' -f $PnpClass, $ImageClassGuid
    $FilterDescription = 'ClassGuid = Imaging device class'
}
else {
    $clauses = @()
    foreach ($pattern in $ScannerDeviceIdPatterns) { $clauses += ('{0}.DeviceID like "{1}"' -f $PnpClass, $pattern) }
    foreach ($pattern in $ScannerNamePatterns)     { $clauses += ('{0}.Name like "{1}"' -f $PnpClass, $pattern) }
    if ($clauses.Count -eq 0) {
        throw 'No scanner patterns defined. Fill $ScannerDeviceIdPatterns / $ScannerNamePatterns or use -UseClassGuid.'
    }
    $ScannerFilter = $clauses -join ' OR '
    $FilterDescription = 'device name / USB vendor ID patterns'
}

$CollectionSelect = @"
SELECT DISTINCT SMS_R_SYSTEM.ResourceID, SMS_R_SYSTEM.ResourceType, SMS_R_SYSTEM.Name, SMS_R_SYSTEM.SMSUniqueIdentifier, SMS_R_SYSTEM.ResourceDomainORWorkgroup, SMS_R_SYSTEM.Client
FROM SMS_R_System
INNER JOIN $PnpClass ON $PnpClass.ResourceID = SMS_R_System.ResourceId
"@

$AllQuery = "$CollectionSelect`r`nWHERE $ScannerFilter"

$DiscoverQuery = "SELECT $PnpClass.Name, $PnpClass.DeviceID, $PnpClass.ResourceID FROM $PnpClass WHERE $ScannerFilter"

function ConvertTo-WqlLiteral {
    # Makes a device name safe inside a double-quoted WQL string.
    param([string]$Text)
    return $Text.Replace('\', '\\').Replace('"', '\"')
}

# ============================================================================
# Connect to MECM
# ============================================================================

if (-not (Get-Module ConfigurationManager -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrEmpty($ENV:SMS_ADMIN_UI_PATH)) {
        throw "SMS_ADMIN_UI_PATH is not set. Run this from a machine with the MECM admin console installed."
    }
    $modulePath = Join-Path (Split-Path $ENV:SMS_ADMIN_UI_PATH -Parent) "ConfigurationManager.psd1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath
    }
    else {
        throw "ConfigurationManager module not found. Run this from a machine with the MECM admin console installed."
    }
}

$OriginalLocation = Get-Location

if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer | Out-Null
}
Set-Location "${SiteCode}:"

$failed = 0

try {
    # ========================================================================
    # Discover mode
    # ========================================================================

    if ($Discover) {
        Write-Host "Querying hardware inventory ($FilterDescription)..."

        try {
            $found = @(Invoke-CMWmiQuery -Query $DiscoverQuery -Option Fast)
        }
        catch {
            if ($UseClassGuid) {
                Write-Host "Query failed. -UseClassGuid needs the 'Class Guid' property enabled on PNP Device Driver (Win32_PnpEntity) in hardware inventory." -ForegroundColor Red
            }
            throw
        }

        if ($found.Count -eq 0) {
            Write-Host "No matching devices in inventory." -ForegroundColor Yellow
            if ($UseClassGuid) {
                Write-Host "If 'Class Guid' was only just enabled, wait for a hardware inventory cycle."
            }
            return
        }

        $models = @(
            $found |
                Where-Object { -not [string]::IsNullOrEmpty([string]$_.Name) } |
                Group-Object -Property { ([string]$_.Name).Trim() } |
                ForEach-Object {
                    $sampleId = [string]($_.Group | Select-Object -First 1).DeviceID
                    $vidPid = ''
                    if ($sampleId -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
                        $vidPid = ('{0}:{1}' -f $Matches[1], $Matches[2]).ToUpper()
                    }
                    [pscustomobject]@{
                        Name    = $_.Name
                        Devices = @($_.Group | ForEach-Object { $_.ResourceID } | Sort-Object -Unique).Count
                        VidPid  = $vidPid
                    }
                } |
                Sort-Object -Property @{ Expression = 'Devices'; Descending = $true }, Name
        )

        Write-Host ""
        Write-Host "=== Paste over `$ScannerModels, then merge variants and remove non-scanners ===" -ForegroundColor Cyan
        Write-Host '$ScannerModels = [ordered]@{'
        foreach ($model in $models) {
            $key   = ('Scanners: ' + $model.Name).Replace("'", "''")
            $value = (ConvertTo-WqlLiteral $model.Name).Replace("'", "''")
            Write-Host ("    '{0}' = '{1}'    # {2} device(s)" -f $key, $value, $model.Devices)
        }
        Write-Host '}'
        Write-Host ""
        Write-Host ("{0} distinct name(s) across {1} inventory row(s)." -f $models.Count, $found.Count)
        Write-Host ""

        # Objects go to the pipeline so the list can be exported or sorted.
        $models
        return
    }

    # ========================================================================
    # Create mode
    # ========================================================================

    if ($ScannerModels.Count -eq 0) {
        Write-Host "`$ScannerModels is empty; only the parent collection will be created. Run -Discover to get the model list." -ForegroundColor Yellow
    }

    if (-not (Get-CMDeviceCollection -Name $LimitingCollectionName)) {
        throw "Limiting collection '$LimitingCollectionName' not found."
    }

    $dailySchedule = New-CMSchedule -RecurInterval Days -RecurCount 1

    $created = New-Object System.Collections.ArrayList
    $skipped = New-Object System.Collections.ArrayList
    $parentCreated = $false

    # ---- Parent collection --------------------------------------------------

    if (Get-CMDeviceCollection -Name $AllCollectionName) {
        Write-Host "Exists, skipped: $AllCollectionName" -ForegroundColor Yellow
        [void]$skipped.Add($AllCollectionName)
    }
    else {
        Write-Host "Creating collection: $AllCollectionName"

        New-CMDeviceCollection `
            -Name $AllCollectionName `
            -LimitingCollectionName $LimitingCollectionName `
            -RefreshType Periodic `
            -RefreshSchedule $dailySchedule `
            -Comment "Devices with a scanner in hardware inventory ($FilterDescription). Auto-populated via WQL against $PnpClass." | Out-Null

        Add-CMDeviceCollectionQueryMembershipRule `
            -CollectionName $AllCollectionName `
            -QueryExpression $AllQuery `
            -RuleName 'Scanners (all models)'

        Write-Host "  Created and query rule attached." -ForegroundColor Green
        [void]$created.Add($AllCollectionName)
        $parentCreated = $true
    }

    # ---- One collection per model -------------------------------------------

    foreach ($entry in $ScannerModels.GetEnumerator()) {
        $collectionName = [string]$entry.Key
        $namePattern    = [string]$entry.Value

        if ([string]::IsNullOrEmpty($collectionName.Trim()) -or [string]::IsNullOrEmpty($namePattern.Trim())) {
            Write-Host "Skipped an entry with an empty name or pattern." -ForegroundColor Yellow
            continue
        }

        try {
            if (Get-CMDeviceCollection -Name $collectionName) {
                Write-Host "Exists, skipped: $collectionName" -ForegroundColor Yellow
                [void]$skipped.Add($collectionName)
                continue
            }

            Write-Host "Creating collection: $collectionName"

            $modelQuery = '{0}{1}WHERE {2}.Name like "{3}"' -f $CollectionSelect, "`r`n", $PnpClass, $namePattern

            New-CMDeviceCollection `
                -Name $collectionName `
                -LimitingCollectionName $AllCollectionName `
                -RefreshType Periodic `
                -RefreshSchedule $dailySchedule `
                -Comment "Devices with a PnP device named like '$namePattern'. Auto-populated via WQL against $PnpClass." | Out-Null

            Add-CMDeviceCollectionQueryMembershipRule `
                -CollectionName $collectionName `
                -QueryExpression $modelQuery `
                -RuleName "Device name like $namePattern"

            Write-Host "  Created and query rule attached." -ForegroundColor Green
            [void]$created.Add($collectionName)
        }
        catch {
            $failed++
            Write-Host "  FAILED: $collectionName -- $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # ---- Trigger initial population -----------------------------------------
    # Updating a new parent also evaluates the collections it limits. When the
    # parent already existed, update the newly created model collections.

    Write-Host ""
    if ($created.Count -gt 0) {
        Write-Host "Triggering initial collection evaluation..."
        if ($parentCreated) {
            Invoke-CMCollectionUpdate -Name $AllCollectionName
        }
        else {
            foreach ($name in $created) { Invoke-CMCollectionUpdate -Name $name }
        }
        Write-Host "  Evaluation queued. Membership populates within a few minutes." -ForegroundColor Green
    }
    else {
        Write-Host "Nothing new to create."
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Limiting collection: $LimitingCollectionName"
    Write-Host "Parent collection:   $AllCollectionName"
    Write-Host "Scanner filter:      $FilterDescription"
    Write-Host "Created:             $($created.Count)"
    Write-Host "Already existed:     $($skipped.Count)"
    Write-Host "Failed:              $failed"
    Write-Host "Refresh:             Daily full (no incremental)"
    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "  1. Wait a few minutes, then verify membership counts in the console."
    Write-Host "  2. If model collections are still empty after the parent has members,"
    Write-Host "     right-click the parent and choose Update Membership."
    Write-Host "  3. An existing collection is never changed. To change a pattern, delete"
    Write-Host "     that collection and re-run."
}
finally {
    Set-Location $OriginalLocation
}

if ($failed -gt 0) { exit 1 }
