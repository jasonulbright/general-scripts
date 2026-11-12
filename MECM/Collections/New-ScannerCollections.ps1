<#
.SYNOPSIS
    Discovers the scanner models present in hardware inventory and walks you
    through creating one MECM device collection per model.

.DESCRIPTION
    Guided and interactive. Nothing to edit or paste:

      1. Queries SMS_G_System_PNP_DEVICE_DRIVER for scanner devices and groups
         them by device name, with a count of devices for each.
      2. Asks whether to create the parent collection ("Scanners: All").
      3. For each discovered model, shows the name and device count and asks:
           [Y]es   create a collection for this model
           [N]o    skip it (default, just press Enter)
           [E]dit  change the collection name and/or the name pattern first,
                   e.g. widen a pattern so one collection covers the variants
                   of a model
           [A]ll   yes to this and every remaining model
           [Q]uit  stop asking; keep what was already chosen
         Models whose collection already exists are shown and not asked about.
      4. Shows the plan and asks once more before creating anything.

    Existing collections are never modified, so the script is safe to re-run
    when new models show up in inventory.

    Switches for unattended use:
      -Discover   List models and counts, create nothing. Output objects can
                  be piped to Export-Csv.
      -All        Create the parent and a collection for every discovered
                  model without prompting.

    What counts as a scanner (discovery and the parent collection use the same
    filter, so what you are shown is what the parent will contain):

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

    Model collections match on device name only: the exact discovered name,
    or Name like "<pattern>" if you chose Edit and typed one. They are limited to the parent collection, or to -LimitingCollectionName if you
    decline the parent.

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

.PARAMETER CollectionPrefix
    Prefix for model collection names. Default: "Scanners: ".

.PARAMETER UseClassGuid
    Identify scanners by the Imaging device class GUID instead of name and USB
    vendor ID. See the requirement in the description.

.PARAMETER Discover
    List scanner models found in inventory and exit. Creates nothing.

.PARAMETER All
    Create the parent and every discovered model collection without prompting.

.EXAMPLE
    .\New-ScannerCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local

    Guided run: discover, answer per model, confirm, create.

.EXAMPLE
    .\New-ScannerCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -Discover |
        Export-Csv .\scanner-models.csv -NoTypeInformation

.EXAMPLE
    .\New-ScannerCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -All -UseClassGuid

.NOTES
    Inventory is a snapshot: a scanner that was unplugged or powered off when
    hardware inventory ran is not in the data until a later cycle sees it.

    USB vendor IDs are from the public USB-IF list (04C5 Fujitsu, 1083 Canon
    Electronics). 04C5 also appears on Fujitsu-built PCs; if you have those,
    expect non-scanner names in the list and answer No to them.

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

    [string]$CollectionPrefix = 'Scanners: ',

    [switch]$UseClassGuid,

    [switch]$Discover,

    [switch]$All
)

$ErrorActionPreference = 'Stop'

if ($Discover -and $All) { throw 'Use either -Discover or -All, not both.' }

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

# ============================================================================
# Helpers
# ============================================================================

function ConvertTo-WqlString {
    # Makes text safe inside a double-quoted WQL string.
    param([string]$Text)
    return $Text.Replace('\', '\\').Replace('"', '\"')
}

function Read-Choice {
    # Asks until one of the allowed single letters is entered. Enter = default.
    param([string]$Prompt, [string[]]$Allowed, [string]$Default)
    while ($true) {
        $answer = [string](Read-Host -Prompt $Prompt)
        $answer = $answer.Trim().ToUpper()
        if ($answer -eq '') { return $Default }
        $letter = $answer.Substring(0, 1)
        if ($Allowed -contains $letter) { return $letter }
        Write-Host ("  Please answer with one of: {0}" -f ($Allowed -join ', ')) -ForegroundColor Yellow
    }
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
    # 1. Discover
    # ========================================================================

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

    $found = @($found | Where-Object { -not [string]::IsNullOrEmpty(([string]$_.Name).Trim()) })

    if ($found.Count -eq 0) {
        Write-Host "No matching devices in inventory. Nothing to create." -ForegroundColor Yellow
        if ($UseClassGuid) {
            Write-Host "If 'Class Guid' was only just enabled, wait for a hardware inventory cycle."
        }
        return
    }

    $totalDevices = @($found | ForEach-Object { $_.ResourceID } | Sort-Object -Unique).Count

    $models = @(
        $found |
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

    Write-Host ("Found {0} model name(s) on {1} device(s)." -f $models.Count, $totalDevices) -ForegroundColor Green

    if ($Discover) {
        # Read-only: objects go to the pipeline so the list can be exported.
        $models
        return
    }

    if (-not (Get-CMDeviceCollection -Name $LimitingCollectionName)) {
        throw "Limiting collection '$LimitingCollectionName' not found."
    }

    # ========================================================================
    # 2. Choose
    # ========================================================================

    $plan = New-Object System.Collections.ArrayList     # model collections to create
    $existingCount = 0

    # ---- Parent -------------------------------------------------------------

    $parentExists = [bool](Get-CMDeviceCollection -Name $AllCollectionName)
    $createParent = $false

    Write-Host ""
    if ($parentExists) {
        Write-Host "Parent collection '$AllCollectionName' already exists; model collections will be limited to it."
        $existingCount++
    }
    elseif ($All) {
        $createParent = $true
    }
    else {
        Write-Host "Parent collection '$AllCollectionName' would hold all $totalDevices device(s) with a scanner."
        $answer = Read-Choice -Prompt "Create it? [Y]es / [N]o (default Y)" -Allowed @('Y', 'N') -Default 'Y'
        $createParent = ($answer -eq 'Y')
        if (-not $createParent) {
            Write-Host "  Model collections will be limited to '$LimitingCollectionName' instead."
        }
    }

    $modelLimit = $LimitingCollectionName
    if ($parentExists -or $createParent) { $modelLimit = $AllCollectionName }

    # ---- Models -------------------------------------------------------------

    $yesToAll = [bool]$All
    $index = 0

    foreach ($model in $models) {
        $index++
        $collectionName = $CollectionPrefix + $model.Name
        $operator       = '='      # exact device name unless edited
        $pattern        = ConvertTo-WqlString $model.Name

        Write-Host ""
        Write-Host ("[{0}/{1}] {2}   {3} device(s)   {4}" -f $index, $models.Count, $model.Name, $model.Devices, $model.VidPid) -ForegroundColor Cyan

        if (Get-CMDeviceCollection -Name $collectionName) {
            Write-Host "  Collection '$collectionName' already exists; skipped."
            $existingCount++
            continue
        }

        $answer = 'Y'
        if (-not $yesToAll) {
            $answer = Read-Choice -Prompt "  Create '$collectionName'? [Y]es / [N]o / [E]dit / [A]ll / [Q]uit (default N)" -Allowed @('Y', 'N', 'E', 'A', 'Q') -Default 'N'
        }

        if ($answer -eq 'Q') { Write-Host "  Stopped asking."; break }
        if ($answer -eq 'N') { continue }
        if ($answer -eq 'A') { $yesToAll = $true }

        if ($answer -eq 'E') {
            $typedName = ([string](Read-Host -Prompt "  Collection name (Enter keeps '$collectionName')")).Trim()
            if ($typedName -ne '') { $collectionName = $typedName }

            Write-Host "  Name pattern: % matches any run of characters, so <model>% covers every variant of a model."
            $typedPattern = ([string](Read-Host -Prompt "  Pattern (Enter keeps the exact name)")).Trim()
            if ($typedPattern -ne '') {
                $operator = 'like'
                $pattern  = ConvertTo-WqlString $typedPattern
            }

            if (Get-CMDeviceCollection -Name $collectionName) {
                Write-Host "  Collection '$collectionName' already exists; skipped." -ForegroundColor Yellow
                $existingCount++
                continue
            }
        }

        if (@($plan | Where-Object { $_.Name -eq $collectionName }).Count -gt 0) {
            Write-Host "  '$collectionName' is already in the plan; skipped." -ForegroundColor Yellow
            continue
        }

        [void]$plan.Add([pscustomobject]@{ Name = $collectionName; Operator = $operator; Pattern = $pattern })
        Write-Host "  Added to plan." -ForegroundColor Green
    }

    # ========================================================================
    # 3. Confirm
    # ========================================================================

    Write-Host ""
    Write-Host "=== Plan ===" -ForegroundColor Cyan
    if ($createParent) { Write-Host ("  {0}   (parent, limited to '{1}')" -f $AllCollectionName, $LimitingCollectionName) }
    foreach ($item in $plan) { Write-Host ("  {0}   (device name {1} `"{2}`", limited to '{3}')" -f $item.Name, $item.Operator, $item.Pattern, $modelLimit) }

    if ((-not $createParent) -and ($plan.Count -eq 0)) {
        Write-Host "  Nothing selected. No changes made."
        return
    }

    if (-not $All) {
        $go = Read-Choice -Prompt "Create these collections now? [Y]es / [N]o (default N)" -Allowed @('Y', 'N') -Default 'N'
        if ($go -ne 'Y') {
            Write-Host "Cancelled. No changes made."
            return
        }
    }

    # ========================================================================
    # 4. Create
    # ========================================================================

    $dailySchedule = New-CMSchedule -RecurInterval Days -RecurCount 1
    $created = New-Object System.Collections.ArrayList

    Write-Host ""
    if ($createParent) {
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
    }

    foreach ($item in $plan) {
        try {
            Write-Host "Creating collection: $($item.Name)"

            $modelQuery = '{0}{1}WHERE {2}.Name {3} "{4}"' -f $CollectionSelect, "`r`n", $PnpClass, $item.Operator, $item.Pattern

            New-CMDeviceCollection `
                -Name $item.Name `
                -LimitingCollectionName $modelLimit `
                -RefreshType Periodic `
                -RefreshSchedule $dailySchedule `
                -Comment "Devices with a PnP device whose name $($item.Operator) '$($item.Pattern)'. Auto-populated via WQL against $PnpClass." | Out-Null

            Add-CMDeviceCollectionQueryMembershipRule `
                -CollectionName $item.Name `
                -QueryExpression $modelQuery `
                -RuleName 'Scanner device name'

            Write-Host "  Created and query rule attached." -ForegroundColor Green
            [void]$created.Add($item.Name)
        }
        catch {
            $failed++
            Write-Host "  FAILED: $($item.Name) -- $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # ---- Trigger initial population -----------------------------------------
    # Updating a new parent also evaluates the collections it limits. When no
    # parent was created, update the new model collections directly.

    Write-Host ""
    if ($created.Count -gt 0) {
        Write-Host "Triggering initial collection evaluation..."
        if ($createParent) {
            Invoke-CMCollectionUpdate -Name $AllCollectionName
        }
        else {
            foreach ($name in $created) { Invoke-CMCollectionUpdate -Name $name }
        }
        Write-Host "  Evaluation queued. Membership populates within a few minutes." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Scanner filter:      $FilterDescription"
    Write-Host "Models discovered:   $($models.Count)"
    Write-Host "Created:             $($created.Count)"
    Write-Host "Already existed:     $existingCount"
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
