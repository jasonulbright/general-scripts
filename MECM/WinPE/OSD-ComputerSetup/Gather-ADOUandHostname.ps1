<#
.SYNOPSIS
    Captures hostname and Active Directory OU from a live OS prior to OSD
    refresh, writing values to MECM Task Sequence variables for use after
    the WinPE transition.

.DESCRIPTION
    Runs in the full OS during the pre-WinPE phase of a refresh task
    sequence. Captures:
      1. Current hostname into OSDComputerName
      2. Current AD OU into OSDDomainOUName (LDAP:// prefixed)
    so the rebuilt machine retains its identity and OU placement.

    Intended to run only on the refresh path (TS launched from Windows).
    Gate the step with condition: _SMSTSLaunchMode equals "SMS".

.NOTES
    Author: <name>
    Last Updated: <date>
    Requires: Domain-joined machine, network connectivity to a DC,
                  step must run in full OS (not WinPE).
                  PowerShell 5.1 (Windows native).
    Encoding: Save as ANSI or UTF-8 WITHOUT BOM.
    TS Variables: Reads - none
                  Writes - OSDComputerName, OSDDomainOUName
#>

# ============================================================================
# Initialize TS environment COM object - gives us read/write access to the
# task sequence variable store. Values written here persist across the
# WinPE transition via the SMSTS state store.
# ============================================================================
$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment

# ============================================================================
# Logging helper - Write-Host output is captured to smsts.log automatically.
# Bracketed prefix makes entries greppable in CMTrace.
# ============================================================================
function Write-TSLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [Capture-HostAndOU] [$Level] $Message"
}

Write-TSLog "Starting capture of hostname and OU from live OS"

# ============================================================================
# Capture hostname from environment variable (always populated, no WMI or
# registry round-trip). Written to OSDComputerName, the built-in TS variable
# consumed by Apply Operating System / Apply Network Settings.
# ============================================================================
$computerName = $env:COMPUTERNAME
$tsenv.Value("OSDComputerName") = $computerName
Write-TSLog "Captured OSDComputerName = $computerName"

# ============================================================================
# Look up current OU from Active Directory using ADSI. No RSAT dependency.
# Searcher binds to the current domain by default - script runs as SYSTEM
# on a domain-joined machine, so no explicit credential needed.
# ============================================================================
try {
    Write-TSLog "Querying AD for computer object: $computerName"

    # objectCategory=computer is indexed in AD and faster than objectClass.
    $searcher = New-Object DirectoryServices.DirectorySearcher
    $searcher.Filter = "(&(objectCategory=computer)(name=$computerName))"
    $searcher.PropertiesToLoad.Add("distinguishedName") | Out-Null
    $result = $searcher.FindOne()

    if (-not $result) {
        # No AD object found - log and exit cleanly without setting OU.
        # Apply Network Settings will fall back to default Computers
        # container, which is recoverable post-deployment.
        Write-TSLog "Computer object not found in AD for $computerName" "WARN"
        Write-TSLog "OSDDomainOUName will not be set - machine will land in default container" "WARN"
        return
    }

    # Extract DN (e.g. CN=PC123,OU=Floor3,OU=Workstations,DC=contoso,DC=com)
    # and strip the leading CN= component to get the parent OU path.
    $dn = $result.Properties["distinguishedname"][0]
    $ouPath = $dn -replace '^CN=[^,]+,',''
    Write-TSLog "Machine resides in: $ouPath"

    # LDAP:// prefix is REQUIRED by Apply Network Settings; without it the
    # domain join silently falls back to the default Computers container.
    $ldapPath = "LDAP://$ouPath"
    $tsenv.Value("OSDDomainOUName") = $ldapPath
    Write-TSLog "Captured OSDDomainOUName = $ldapPath"

} catch {
    # AD query failure - log and continue rather than throw. Refresh should
    # still proceed; downstream domain join will use default container as
    # fallback. Re-running the TS or manually moving the machine post-build
    # is a recoverable outcome; a hard abort here is not.
    Write-TSLog "AD query failed: $($_.Exception.Message)" "ERROR"
    Write-TSLog "Continuing without OSDDomainOUName - machine will land in default container" "WARN"
}

Write-TSLog "Capture step completed"