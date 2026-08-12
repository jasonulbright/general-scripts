<#
.SYNOPSIS
    Creates the 12 MECM device collections that map 1:1 to the New-SpecExecBitmask.ps1
    permutations: CPU vendor x Hyper-Threading state x host role.

.DESCRIPTION
    Creates query-based collections for every combination of:

      Vendor:  Intel (SMS_G_System_PROCESSOR.Manufacturer = GenuineIntel)
               AMD   (SMS_G_System_PROCESSOR.Manufacturer = AuthenticAMD)
      HT/SMT:  Enabled  (any processor: NumberOfLogicalProcessors > NumberOfCores)
               Disabled (all processors: NumberOfLogicalProcessors = NumberOfCores,
                         excluded from the HT-Enabled set via subquery)
      Role:    Workstations   (OS ProductType = 1)
               Servers        (ProductType 2/3, NOT a Hyper-V host)
               Hyper-V Hosts  (ProductType 2/3 with the Hyper-V server feature installed,
                               per SMS_G_System_SERVER_FEATURE)

    Default names ("SpecExec: " prefix):

      SpecExec: Workstations - Intel - HT Enabled     SpecExec: Servers - Intel - HT Enabled
      SpecExec: Workstations - Intel - HT Disabled    SpecExec: Servers - Intel - HT Disabled
      SpecExec: Workstations - AMD - HT Enabled       SpecExec: Servers - AMD - HT Enabled
      SpecExec: Workstations - AMD - HT Disabled      SpecExec: Servers - AMD - HT Disabled
      SpecExec: Hyper-V Hosts - Intel - HT Enabled    SpecExec: Hyper-V Hosts - AMD - HT Enabled
      SpecExec: Hyper-V Hosts - Intel - HT Disabled   SpecExec: Hyper-V Hosts - AMD - HT Disabled

    Deploy the remediation produced by Registry/New-SpecExecBitmask.ps1 to the matching
    collection: HT state picks the FeatureSettingsOverride value, vendor picks which CVE
    bits apply, and the Hyper-V Hosts collections take the variant that also writes
    MinVmVersionForCpuBasedMitigations.

    Hypervisor notes:
      - Only Windows Hyper-V hosts get their own collections. VMware ESXi and Xen/XenServer
        hypervisors do not run the ConfigMgr client, so they cannot be collection members;
        their speculative-execution microcode/scheduler mitigations are managed through
        vendor tooling (vCenter/VUM, XenCenter), not MECM.
      - Windows guests on any hypervisor (Hyper-V, ESXi, Xen) are ordinary devices and land
        in the Workstations/Servers collections. Their PROCESSOR inventory reflects the
        virtual CPU topology, so a guest's HT bucket describes its vCPU layout, not the
        physical host. Guest registry mitigations still apply per vendor guidance; host-side
        exposure (L1TF/MDS scheduler decisions) is fixed at the hypervisor.
      - Hyper-V detection uses SMS_G_System_SERVER_FEATURE (Name = "Hyper-V"). This class
        only exists in the site schema when the "Server Feature" hardware inventory class
        is enabled in client settings; the script preflights for it and refuses to create
        collections if it is absent, because the Servers queries also reference it (in the
        NOT IN exclusion) and every rule referencing a missing class fails WQL validation.
        If the class exists but inventory collection is later disabled, the Hyper-V
        collections drain empty and Hyper-V hosts fall through to the Servers collections.

    Membership refresh: incremental enabled (so newly inventoried hosts populate fast),
    plus a daily full evaluation.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER LimitingCollectionName
    Parent / limiting collection for all 12 collections. Default: "All Systems".
    Use a tighter limit (e.g. "All Windows Devices") to keep non-Windows or
    unmanaged endpoints out.

.PARAMETER CollectionNamePrefix
    Prefix applied to every collection name. Default: "SpecExec: ".

.EXAMPLE
    .\New-SpecExecTargetCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local

.EXAMPLE
    .\New-SpecExecTargetCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -LimitingCollectionName "All Windows Devices"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$LimitingCollectionName = 'All Systems',

    [string]$CollectionNamePrefix = 'SpecExec: '
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# WQL builder
# ============================================================================

$SelectClause = @'
SELECT DISTINCT SMS_R_SYSTEM.ResourceID, SMS_R_SYSTEM.ResourceType, SMS_R_SYSTEM.Name, SMS_R_SYSTEM.SMSUniqueIdentifier, SMS_R_SYSTEM.ResourceDomainORWorkgroup, SMS_R_SYSTEM.Client
FROM SMS_R_System
INNER JOIN SMS_G_System_PROCESSOR ON SMS_G_System_PROCESSOR.ResourceID = SMS_R_System.ResourceId
INNER JOIN SMS_G_System_OPERATING_SYSTEM ON SMS_G_System_OPERATING_SYSTEM.ResourceID = SMS_R_System.ResourceId
'@

# Any-processor HT-enabled set; the HT-Disabled predicate excludes it so multi-socket
# boxes with mixed inventory rows never land in both buckets.
$HtEnabledSubquery = @'
SELECT SMS_R_SYSTEM.ResourceID FROM SMS_R_System
    INNER JOIN SMS_G_System_PROCESSOR ON SMS_G_System_PROCESSOR.ResourceID = SMS_R_System.ResourceId
    WHERE SMS_G_System_PROCESSOR.NumberOfLogicalProcessors > SMS_G_System_PROCESSOR.NumberOfCores
'@

$HyperVSubquery = @'
SELECT SMS_R_SYSTEM.ResourceID FROM SMS_R_System
    INNER JOIN SMS_G_System_SERVER_FEATURE ON SMS_G_System_SERVER_FEATURE.ResourceID = SMS_R_System.ResourceId
    WHERE SMS_G_System_SERVER_FEATURE.Name = "Hyper-V"
'@

function New-SpecExecWql {
    param(
        [ValidateSet('Intel', 'AMD')]
        [string]$Vendor,

        [ValidateSet('Workstation', 'Server', 'HyperVHost')]
        [string]$Role,

        [bool]$HtEnabled
    )

    $vendorString = if ($Vendor -eq 'Intel') { 'GenuineIntel' } else { 'AuthenticAMD' }

    $where = @("SMS_G_System_PROCESSOR.Manufacturer = `"$vendorString`"")

    switch ($Role) {
        'Workstation' {
            $where += 'SMS_G_System_OPERATING_SYSTEM.ProductType = 1'
        }
        'Server' {
            $where += '(SMS_G_System_OPERATING_SYSTEM.ProductType = 2 OR SMS_G_System_OPERATING_SYSTEM.ProductType = 3)'
            $where += "SMS_R_System.ResourceId NOT IN (`n$HyperVSubquery)"
        }
        'HyperVHost' {
            $where += '(SMS_G_System_OPERATING_SYSTEM.ProductType = 2 OR SMS_G_System_OPERATING_SYSTEM.ProductType = 3)'
            $where += "SMS_R_System.ResourceId IN (`n$HyperVSubquery)"
        }
    }

    if ($HtEnabled) {
        $where += 'SMS_G_System_PROCESSOR.NumberOfLogicalProcessors > SMS_G_System_PROCESSOR.NumberOfCores'
    }
    else {
        $where += 'SMS_G_System_PROCESSOR.NumberOfLogicalProcessors = SMS_G_System_PROCESSOR.NumberOfCores'
        $where += "SMS_R_System.ResourceId NOT IN (`n$HtEnabledSubquery)"
    }

    "$SelectClause`nWHERE " + ($where -join "`nAND ")
}

# ============================================================================
# Collection matrix
# ============================================================================

$roleLabels = @{
    Workstation = 'Workstations'
    Server      = 'Servers'
    HyperVHost  = 'Hyper-V Hosts'
}

$roleComments = @{
    Workstation = 'workstation OS (ProductType 1)'
    Server      = 'server OS (ProductType 2/3) without the Hyper-V role'
    HyperVHost  = 'server OS (ProductType 2/3) with the Hyper-V server feature installed; also needs MinVmVersionForCpuBasedMitigations'
}

$Matrix = foreach ($role in 'Workstation', 'Server', 'HyperVHost') {
    foreach ($vendor in 'Intel', 'AMD') {
        foreach ($ht in $true, $false) {
            $htLabel = if ($ht) { 'HT Enabled' } else { 'HT Disabled' }
            [pscustomobject]@{
                Name     = '{0}{1} - {2} - {3}' -f $CollectionNamePrefix, $roleLabels[$role], $vendor, $htLabel
                Query    = New-SpecExecWql -Vendor $vendor -Role $role -HtEnabled $ht
                RuleName = '{0} {1} {2}' -f $vendor, $roleLabels[$role], $htLabel
                Comment  = 'Speculative-execution mitigation target: {0} CPUs, Hyper-Threading {1}, {2}. Auto-populated via WQL against SMS_G_System_PROCESSOR / SMS_G_System_OPERATING_SYSTEM{3}. Deploy the matching Registry/New-SpecExecBitmask.ps1 output here.' -f `
                    $vendor,
                    $(if ($ht) { 'enabled' } else { 'disabled' }),
                    $roleComments[$role],
                    $(if ($role -ne 'Workstation') { ' / SMS_G_System_SERVER_FEATURE' } else { '' })
            }
        }
    }
}

# ============================================================================
# Connect to MECM
# ============================================================================

$modulePath = Join-Path (Split-Path $ENV:SMS_ADMIN_UI_PATH -Parent) "ConfigurationManager.psd1"
if (-not (Get-Module ConfigurationManager -ErrorAction SilentlyContinue)) {
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

try {
    # ========================================================================
    # Preflight: SMS_G_System_SERVER_FEATURE must exist in the site schema.
    # 8 of the 12 queries reference it; a missing class fails WQL validation
    # on every one of them, so bail before creating anything.
    # ========================================================================

    try {
        $cimSession = New-CimSession -ComputerName $SiteServer
        try {
            $serverFeatureClass = Get-CimClass -CimSession $cimSession -Namespace "root\sms\site_$SiteCode" -ClassName 'SMS_G_System_SERVER_FEATURE' -ErrorAction SilentlyContinue
        }
        finally {
            Remove-CimSession -CimSession $cimSession
        }
        if (-not $serverFeatureClass) {
            throw "SMS_G_System_SERVER_FEATURE not found in root\sms\site_$SiteCode on $SiteServer. Enable the 'Server Feature' hardware inventory class (Client Settings > Hardware Inventory > Set Classes), wait for a server inventory cycle, then rerun."
        }
    }
    catch [Microsoft.Management.Infrastructure.CimException] {
        Write-Warning "Could not query $SiteServer via CIM to preflight SMS_G_System_SERVER_FEATURE ($($_.Exception.Message)). Continuing; if the class is missing, rule creation fails with a WQL validation error."
    }

    # ========================================================================
    # Refresh schedule: daily full evaluation (incremental also enabled below)
    # ========================================================================

    $dailySchedule = New-CMSchedule -RecurInterval Days -RecurCount 1

    # ========================================================================
    # Create each collection in the matrix
    # ========================================================================

    foreach ($entry in $Matrix) {
        Write-Host "Creating collection: $($entry.Name)"

        if (Get-CMDeviceCollection -Name $entry.Name) {
            Write-Host "  Already exists, skipping." -ForegroundColor Yellow
            continue
        }

        New-CMDeviceCollection `
            -Name $entry.Name `
            -LimitingCollectionName $LimitingCollectionName `
            -RefreshType Both `
            -RefreshSchedule $dailySchedule `
            -Comment $entry.Comment | Out-Null

        Add-CMDeviceCollectionQueryMembershipRule `
            -CollectionName $entry.Name `
            -QueryExpression $entry.Query `
            -RuleName $entry.RuleName

        Write-Host "  Created and query rule attached." -ForegroundColor Green
    }

    # ========================================================================
    # Trigger initial population
    # ========================================================================

    Write-Host ""
    Write-Host "Triggering initial collection evaluation..."

    foreach ($entry in $Matrix) {
        Invoke-CMCollectionUpdate -Name $entry.Name
    }

    Write-Host "  Evaluation queued. Membership populates within a few minutes." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Limiting collection: $LimitingCollectionName"
    foreach ($entry in $Matrix) {
        Write-Host "  $($entry.Name)"
    }
    Write-Host "Refresh:             Incremental + Daily full"
    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "  1. Wait a few minutes, then verify membership counts in the console."
    Write-Host "  2. Sanity-check the Hyper-V Hosts collections: if empty despite known hosts,"
    Write-Host "     confirm the Server Feature hardware inventory class is enabled."
    Write-Host "  3. Generate one remediation script per collection with Registry/New-SpecExecBitmask.ps1"
    Write-Host "     (HT state + vendor CVEs; check the Hyper-V box for the Hyper-V Hosts collections)"
    Write-Host "     and deploy each to its matching collection."
}
finally {
    Set-Location $OriginalLocation
}
