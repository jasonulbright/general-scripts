<#
.SYNOPSIS
    Generates a self-contained HTML client health report for support triage.

.DESCRIPTION
    Gathers local device state (OS, uptime, disks, RAM, network, ADOU, pending
    reboot, Registry.pol health, installed apps, MECM client info, MECM log
    errors) and writes a single self-contained HTML file to the output folder,
    then launches it in Microsoft Edge. Runs fully as standard user; when run
    elevated, additionally pulls Windows event log errors and admin-restricted
    log files.

    Intended use: a technician asks the end user to double-click the desktop
    shortcut before submitting a ticket. The resulting .html attaches to the
    ticket and gives support everything they need for first-pass triage
    without remoting in.

.PARAMETER OutputDir
    Folder to write the report to. Default: C:\temp.

.PARAMETER NoLaunch
    Skip auto-launching Edge. Report is still written.

.EXAMPLE
    .\client-check.ps1

.EXAMPLE
    .\client-check.ps1 -OutputDir D:\support -NoLaunch
#>

[CmdletBinding()]
param(
    [string]$OutputDir = 'C:\temp',
    [int]$HoursBack    = 24,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$script:Version = '1.0.0'
$script:Start   = Get-Date

# --- helpers ---------------------------------------------------------------

function Invoke-Safe {
    param(
        [Parameter(Mandatory)][scriptblock]$Block,
        $Fallback = $null
    )
    try { & $Block } catch { $Fallback }
}

function Test-Elevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function HtmlEnc {
    param([string]$s)
    if ($null -eq $s) { return '' }
    [System.Net.WebUtility]::HtmlEncode($s)
}

function Format-Bytes {
    param([double]$bytes)
    if ($bytes -ge 1TB) { return ('{0:N2} TB' -f ($bytes / 1TB)) }
    if ($bytes -ge 1GB) { return ('{0:N2} GB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N2} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N2} KB' -f ($bytes / 1KB)) }
    return ('{0} B' -f [int]$bytes)
}

function Format-TimeSpan {
    param([TimeSpan]$ts)
    if ($null -eq $ts) { return 'unknown' }
    $parts = @()
    if ($ts.Days    -gt 0) { $parts += "$($ts.Days)d" }
    if ($ts.Hours   -gt 0) { $parts += "$($ts.Hours)h" }
    if ($ts.Minutes -gt 0 -and $ts.Days -eq 0) { $parts += "$($ts.Minutes)m" }
    if ($parts.Count -eq 0) { return "$($ts.Seconds)s" }
    $parts -join ' '
}

# --- gatherers -------------------------------------------------------------

function Get-DeviceSummary {
    $os  = Invoke-Safe { Get-CimInstance -ClassName Win32_OperatingSystem }
    $cs  = Invoke-Safe { Get-CimInstance -ClassName Win32_ComputerSystem }
    $bios = Invoke-Safe { Get-CimInstance -ClassName Win32_BIOS }

    $lastBoot = $null
    $uptime   = $null
    if ($os -and $os.LastBootUpTime) {
        $lastBoot = $os.LastBootUpTime
        $uptime   = (Get-Date) - $lastBoot
    }

    [pscustomobject]@{
        Hostname      = $env:COMPUTERNAME
        User          = "$env:USERDOMAIN\$env:USERNAME"
        OsCaption     = if ($os) { $os.Caption } else { 'unknown' }
        OsVersion     = if ($os) { $os.Version } else { 'unknown' }
        OsBuild       = if ($os) { $os.BuildNumber } else { 'unknown' }
        InstallDate   = if ($os) { $os.InstallDate } else { $null }
        LastBoot      = $lastBoot
        Uptime        = $uptime
        Manufacturer  = if ($cs)   { $cs.Manufacturer } else { 'unknown' }
        Model         = if ($cs)   { $cs.Model }        else { 'unknown' }
        Serial        = if ($bios) { $bios.SerialNumber } else { 'unknown' }
        TotalRamBytes = if ($cs)   { [double]$cs.TotalPhysicalMemory } else { 0 }
        DomainOrWG    = if ($cs)   { if ($cs.PartOfDomain) { $cs.Domain } else { "WORKGROUP: $($cs.Workgroup)" } } else { 'unknown' }
        DnsHostName   = if ($cs)   { "$($cs.DNSHostName).$($cs.Domain)" } else { $env:COMPUTERNAME }
    }
}

function Get-RebootStatus {
    $reasons = New-Object System.Collections.Generic.List[string]

    $keys = @(
        @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Reason='Component Based Servicing' },
        @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'; Reason='CBS reboot in progress' },
        @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'; Reason='CBS packages pending' },
        @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Reason='Windows Update reboot required' },
        @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'; Reason='WU post-reboot reporting' }
    )
    foreach ($k in $keys) {
        if (Test-Path $k.Path) { $reasons.Add($k.Reason) | Out-Null }
    }

    $pfro = Invoke-Safe {
        Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
    }
    if ($pfro -and $pfro.PendingFileRenameOperations) {
        $reasons.Add('Pending file rename operations') | Out-Null
    }

    $ccm = Invoke-Safe {
        Invoke-CimMethod -Namespace 'root\ccm\ClientSDK' -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction Stop
    }
    if ($ccm -and $ccm.ReturnValue -eq 0) {
        if ($ccm.IsHardRebootPending) { $reasons.Add('MECM client: hard reboot pending') | Out-Null }
        if ($ccm.RebootPending)       { $reasons.Add('MECM client: reboot pending')      | Out-Null }
    }

    [pscustomobject]@{
        Pending = ($reasons.Count -gt 0)
        Reasons = $reasons.ToArray()
    }
}

function Get-DiskInfo {
    Invoke-Safe {
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
            $free  = [double]$_.FreeSpace
            $total = [double]$_.Size
            $pct   = if ($total -gt 0) { [math]::Round(($free / $total) * 100, 1) } else { 0 }
            [pscustomobject]@{
                Drive     = $_.DeviceID
                Label     = $_.VolumeName
                FileSys   = $_.FileSystem
                FreeBytes = $free
                TotalBytes= $total
                FreePct   = $pct
            }
        }
    } @()
}

function Get-NetworkInfo {
    Invoke-Safe {
        Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
            $ifIndex = $_.ifIndex
            $ipv4 = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                     Where-Object { $_.IPAddress -notmatch '^169\.254\.' } |
                     Select-Object -ExpandProperty IPAddress) -join ', '
            $ipv6 = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                     Where-Object { $_.IPAddress -notmatch '^fe80::' } |
                     Select-Object -ExpandProperty IPAddress) -join ', '
            $cfg  = Invoke-Safe { Get-NetIPConfiguration -InterfaceIndex $ifIndex -ErrorAction Stop }
            $gw   = if ($cfg -and $cfg.IPv4DefaultGateway) { ($cfg.IPv4DefaultGateway.NextHop -join ', ') } else { '' }
            $dns  = if ($cfg -and $cfg.DNSServer) { (($cfg.DNSServer | ForEach-Object { $_.ServerAddresses }) -join ', ') } else { '' }
            [pscustomobject]@{
                Name        = $_.Name
                Description = $_.InterfaceDescription
                Mac         = $_.MacAddress
                LinkSpeed   = $_.LinkSpeed
                Ipv4        = $ipv4
                Ipv6        = $ipv6
                Gateway     = $gw
                Dns         = $dns
            }
        }
    } @()
}

function Get-DirectoryJoinInfo {
    $result = [pscustomobject]@{
        DistinguishedName = ''
        AzureAdJoined     = $false
        DomainJoined      = $false
        TenantName        = ''
        EnterpriseJoined  = $false
    }

    $dn = Invoke-Safe {
        $searcher = [adsisearcher]"(&(objectCategory=computer)(cn=$env:COMPUTERNAME))"
        $searcher.PropertiesToLoad.Add('distinguishedname') | Out-Null
        $found = $searcher.FindOne()
        if ($found) { [string]$found.Properties['distinguishedname'][0] } else { '' }
    } ''
    $result.DistinguishedName = $dn

    $dsreg = Invoke-Safe { & dsregcmd.exe /status 2>$null } ''
    if ($dsreg) {
        foreach ($line in $dsreg) {
            if ($line -match '^\s*AzureAdJoined\s*:\s*(YES|NO)')    { $result.AzureAdJoined    = ($Matches[1] -eq 'YES') }
            if ($line -match '^\s*DomainJoined\s*:\s*(YES|NO)')     { $result.DomainJoined     = ($Matches[1] -eq 'YES') }
            if ($line -match '^\s*EnterpriseJoined\s*:\s*(YES|NO)') { $result.EnterpriseJoined = ($Matches[1] -eq 'YES') }
            if ($line -match '^\s*TenantName\s*:\s*(.+?)\s*$')      { $result.TenantName       = $Matches[1] }
        }
    }
    $result
}

function Get-RegistryPolStatus {
    $targets = @(
        @{ Scope='Machine'; Path="$env:SystemRoot\System32\GroupPolicy\Machine\Registry.pol" },
        @{ Scope='User';    Path="$env:SystemRoot\System32\GroupPolicy\User\Registry.pol" }
    )
    foreach ($t in $targets) {
        $status = [pscustomobject]@{
            Scope     = $t.Scope
            Path      = $t.Path
            Exists    = $false
            Size      = 0
            Modified  = $null
            Header    = 'n/a'
            Healthy   = $false
            Note      = ''
        }
        if (Test-Path -LiteralPath $t.Path) {
            $status.Exists = $true
            $fi = Get-Item -LiteralPath $t.Path
            $status.Size     = $fi.Length
            $status.Modified = $fi.LastWriteTime
            if ($fi.Length -lt 8) {
                $status.Header = 'too small'
                $status.Note   = 'File under 8 bytes; likely empty or corrupted.'
            } else {
                try {
                    $fs = [System.IO.File]::OpenRead($t.Path)
                    try {
                        $buf = New-Object byte[] 8
                        $null = $fs.Read($buf, 0, 8)
                    } finally { $fs.Dispose() }
                    $magic = [System.Text.Encoding]::ASCII.GetString($buf, 0, 4)
                    $ver   = [BitConverter]::ToUInt32($buf, 4)
                    $status.Header = "$magic v$ver"
                    if ($magic -eq 'PReg' -and $ver -eq 1) {
                        $status.Healthy = $true
                    } else {
                        $status.Note = "Unexpected header (expected 'PReg' v1). Possible corruption; consider resetting local GPO."
                    }
                } catch {
                    $status.Note = "Read failed: $($_.Exception.Message)"
                }
            }
        } else {
            $status.Note = 'File not present (no policy applied at this scope, or GPO engine cleared it).'
            $status.Healthy = $true
        }
        $status
    }
}

function Get-InstalledApps {
    $roots = @(
        @{ Hive='HKLM'; Scope='x64';  Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Hive='HKLM'; Scope='x86';  Path='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Hive='HKCU'; Scope='User'; Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' }
    )
    $apps = New-Object System.Collections.Generic.List[object]
    foreach ($r in $roots) {
        if (-not (Test-Path $r.Path)) { continue }
        Invoke-Safe {
            Get-ChildItem $r.Path -ErrorAction Stop | ForEach-Object {
                $p = $null
                try { $p = Get-ItemProperty $_.PSPath -ErrorAction Stop } catch { return }
                if (-not $p.DisplayName) { return }
                if ($p.SystemComponent -eq 1) { return }
                if ($p.ParentKeyName)      { return }
                $apps.Add([pscustomobject]@{
                    Name      = [string]$p.DisplayName
                    Version   = [string]$p.DisplayVersion
                    Publisher = [string]$p.Publisher
                    Installed = [string]$p.InstallDate
                    Scope     = $r.Scope
                }) | Out-Null
            }
        } | Out-Null
    }
    $apps | Sort-Object Name, Version
}

function Get-MecmClientInfo {
    $info = [pscustomobject]@{
        Installed       = $false
        ClientVersion   = ''
        SiteCode        = ''
        ManagementPoint = ''
        LastPolicyEval  = $null
        LastHwInv       = $null
        LastSwInv       = $null
        CacheSize       = 0
        LogPath         = "$env:SystemRoot\CCM\Logs"
    }
    $sms = Invoke-Safe { Get-CimInstance -Namespace 'root\ccm' -ClassName SMS_Client -ErrorAction Stop }
    if ($sms) {
        $info.Installed     = $true
        $info.ClientVersion = $sms.ClientVersion
    }
    $auth = Invoke-Safe { Get-CimInstance -Namespace 'root\ccm' -ClassName SMS_Authority -ErrorAction Stop } | Select-Object -First 1
    if ($auth) {
        $info.SiteCode        = $auth.Name -replace '^SMS:',''
        $info.ManagementPoint = $auth.CurrentManagementPoint
    }

    $sched = Invoke-Safe { Get-CimInstance -Namespace 'root\ccm\Scheduler' -ClassName CCM_Scheduler_History -ErrorAction Stop } @()
    foreach ($h in $sched) {
        switch ($h.ScheduleID) {
            '{00000000-0000-0000-0000-000000000022}' { $info.LastPolicyEval = $h.LastTriggerTime }
            '{00000000-0000-0000-0000-000000000001}' { $info.LastHwInv      = $h.LastTriggerTime }
            '{00000000-0000-0000-0000-000000000002}' { $info.LastSwInv      = $h.LastTriggerTime }
        }
    }

    $cache = Invoke-Safe { Get-CimInstance -Namespace 'root\ccm\SoftMgmtAgent' -ClassName CacheConfig -ErrorAction Stop } | Select-Object -First 1
    if ($cache) { $info.CacheSize = [int]$cache.Size }
    $info
}

function Read-SharedText {
    # Reads a file that another process may hold open for write (like MECM logs
    # under CcmExec). Mirrors what CMTrace does: FileShare.ReadWrite|Delete.
    param([Parameter(Mandatory)][string]$Path)
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    try {
        $sr = New-Object System.IO.StreamReader($fs, $true)  # detectEncodingFromBOM=true
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

function Get-CmTraceEntries {
    param(
        [Parameter(Mandatory)][string]$BaseName,
        [Parameter(Mandatory)][string]$LogRoot,
        [datetime]$Since,
        [int]$MaxEntries = 20
    )
    $logPath = Join-Path $LogRoot $BaseName
    $loPath  = Join-Path $LogRoot ($BaseName -replace '\.log$', '.lo_')

    $candidates = @($logPath, $loPath) | Where-Object { Test-Path -LiteralPath $_ }
    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Name=$BaseName; Found=$false; Readable=$false; Entries=@();
            CountInWindow=0; CountTotal=0; ReadError=''
        }
    }

    $readErr = ''
    $anyReadable = $false
    $all = New-Object System.Collections.Generic.List[object]
    $pattern = '<!\[LOG\[(?<msg>.*?)\]LOG\]!><time="(?<time>[^"]+)" date="(?<date>[^"]+)" component="(?<comp>[^"]*)" context="[^"]*" type="(?<type>\d)"'
    $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($path in $candidates) {
        $content = $null
        try {
            $content = Read-SharedText -Path $path
            $anyReadable = $true
        } catch {
            if (-not $readErr) { $readErr = $_.Exception.Message }
            continue
        }
        foreach ($m in $regex.Matches($content)) {
            $t = $m.Groups['type'].Value
            if ($t -ne '2' -and $t -ne '3') { continue }
            $parsed = [datetime]::MinValue
            $cleanTime = ($m.Groups['time'].Value -replace '\.\d+[+\-]\d+$','' -replace '[+\-]\d+$','')
            $ok = [datetime]::TryParse(($m.Groups['date'].Value + ' ' + $cleanTime), [ref]$parsed)
            $ts = if ($ok) { $parsed } else { $null }
            $all.Add([pscustomobject]@{
                Timestamp = $ts
                Type      = [int]$t
                Level     = if ($t -eq '3') { 'Error' } else { 'Warning' }
                Component = $m.Groups['comp'].Value
                Message   = $m.Groups['msg'].Value.Trim()
            }) | Out-Null
        }
    }

    if (-not $anyReadable) {
        return [pscustomobject]@{
            Name=$BaseName; Found=$true; Readable=$false; Entries=@();
            CountInWindow=0; CountTotal=0; ReadError=$readErr
        }
    }

    # Dedupe across .log / .lo_ on (ticks|type|component|message)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($e in $all) {
        $ticks = if ($e.Timestamp) { $e.Timestamp.Ticks } else { 0 }
        $key = "$ticks|$($e.Type)|$($e.Component)|$($e.Message)"
        if ($seen.Add($key)) { $unique.Add($e) | Out-Null }
    }

    $inWindow = if ($Since) {
        $unique | Where-Object { $_.Timestamp -and $_.Timestamp -ge $Since }
    } else { $unique }

    $sorted = @($inWindow) | Sort-Object @{Expression={ if ($_.Timestamp) { $_.Timestamp } else { [datetime]::MinValue } }} -Descending
    $top    = $sorted | Select-Object -First $MaxEntries

    [pscustomobject]@{
        Name          = $BaseName
        Found         = $true
        Readable      = $true
        Entries       = @($top)
        CountInWindow = @($inWindow).Count
        CountTotal    = $unique.Count
        ReadError     = ''
    }
}

function Get-MecmLogSet {
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [datetime]$Since
    )
    # SC install chain: policy -> app model -> content -> execution -> updates -> state,
    # plus client plumbing (messaging, location, registration, exec, health) whose failures
    # present as SC symptoms, plus inventory (collection-targeting root cause), plus SC UI log.
    $files = @(
        'ClientIDManagerStartup.log','CcmExec.log','CcmMessaging.log','CcmEval.log','ClientLocation.log','LocationServices.log','StatusAgent.log',
        'PolicyAgent.log','PolicyEvaluator.log',
        'CAS.log','ContentTransferManager.log','DataTransferService.log',
        'AppDiscovery.log','AppEnforce.log','AppIntentEval.log','CIDownloader.log','CITaskMgr.log','DCMAgent.log',
        'WUAHandler.log','UpdatesDeployment.log','UpdatesHandler.log','UpdatesStore.log','ScanAgent.log',
        'InventoryAgent.log','StateMessage.log','ExecMgr.log'
    )
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($f in $files) {
        $results.Add((Get-CmTraceEntries -BaseName $f -LogRoot $LogRoot -Since $Since)) | Out-Null
    }

    # SCClient user log(s): lives in %TEMP% under the user profile; only the running user
    # can read their own. This tool's user-scope execution is the unique access path.
    $scTemp = $env:TEMP
    if ($scTemp -and (Test-Path -LiteralPath $scTemp)) {
        $scFiles = Invoke-Safe {
            Get-ChildItem -LiteralPath $scTemp -Filter 'SCClient_*.log' -File -ErrorAction Stop
        } @()
        foreach ($sc in $scFiles) {
            $results.Add((Get-CmTraceEntries -BaseName $sc.Name -LogRoot $sc.DirectoryName -Since $Since)) | Out-Null
        }
    }

    $results
}

function Get-EventLogErrors {
    param([int]$Hours = 24, [int]$MaxPerLog = 40)
    if (-not (Test-Elevated)) {
        return [pscustomobject]@{ Skipped=$true; Reason='requires admin'; Events=@() }
    }
    $since = (Get-Date).AddHours(-$Hours)
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($logName in @('Application','System')) {
        $items = Invoke-Safe {
            Get-WinEvent -FilterHashtable @{ LogName=$logName; Level=@(1,2,3); StartTime=$since } -MaxEvents $MaxPerLog -ErrorAction Stop
        } @()
        foreach ($e in $items) {
            $events.Add([pscustomobject]@{
                Log       = $logName
                Time      = $e.TimeCreated
                Level     = switch ($e.Level) { 1 {'Critical'} 2 {'Error'} 3 {'Warning'} default {"Lvl$($e.Level)"} }
                Provider  = $e.ProviderName
                Id        = $e.Id
                Message   = ($e.Message -replace '\s+',' ').Trim()
            }) | Out-Null
        }
    }
    [pscustomobject]@{ Skipped=$false; Events=($events | Sort-Object Time -Descending) }
}

# --- HTML builder ----------------------------------------------------------

function New-HtmlReport {
    param(
        $Device, $Reboot, $Disks, $Network, $Directory, $Pol,
        $Apps, $Mecm, $Logs, $EventLog, [bool]$Elevated, [int]$HoursBack
    )

    $title = "Client Check - $($Device.Hostname) - $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"

    # Banner logic
    $uptimeHours = if ($Device.Uptime) { $Device.Uptime.TotalHours } else { 0 }
    $bannerLevel = 'none'
    $bannerMsg   = ''
    if ($Reboot.Pending) {
        $bannerLevel = 'red'
        $bannerMsg   = 'This device has a pending reboot. Please reboot before submitting your ticket.'
    } elseif ($uptimeHours -gt 24) {
        $bannerLevel = 'amber'
        $bannerMsg   = "This device has been running for $([int]$uptimeHours) hours without a reboot. Please reboot before submitting your ticket."
    }

    $sysDrive = ($env:SystemDrive) # typically 'C:'
    $sysDisk  = $Disks | Where-Object { $_.Drive -eq $sysDrive } | Select-Object -First 1
    if (-not $sysDisk) { $sysDisk = $Disks | Select-Object -First 1 }

    $sb = New-Object System.Text.StringBuilder

    $null = $sb.Append(@"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$(HtmlEnc $title)</title>
<style>
  :root {
    --bg:#f4f5f7; --panel:#ffffff; --ink:#1d2430; --muted:#5b6573;
    --line:#e2e5ea; --accent:#1a63b8;
    --red:#b3261e; --redbg:#fde7e7;
    --amber:#8a5a00; --amberbg:#fff4d6;
    --green:#1b6b35; --greenbg:#e4f4ea;
    --mono: 'Cascadia Mono', 'Consolas', 'Lucida Console', monospace;
  }
  * { box-sizing: border-box; }
  html, body { margin:0; padding:0; background:var(--bg); color:var(--ink);
    font-family: 'Segoe UI Variable', 'Segoe UI', Tahoma, Arial, sans-serif; font-size:14px; }
  .wrap { max-width:1280px; margin:0 auto; padding:16px; }
  header { display:flex; align-items:baseline; justify-content:space-between; flex-wrap:wrap; gap:8px; margin-bottom:8px; }
  header h1 { font-size:20px; margin:0; font-weight:600; }
  header .meta { color:var(--muted); font-size:12px; }
  .pill { display:inline-block; padding:2px 8px; border-radius:10px; font-size:11px; font-weight:600; }
  .pill.admin { background:var(--greenbg); color:var(--green); border:1px solid var(--green); }
  .pill.user  { background:var(--amberbg); color:var(--amber); border:1px solid var(--amber); }
  .banner { padding:18px 22px; border-radius:8px; margin:12px 0; font-size:22px; font-weight:700;
    line-height:1.3; border:2px solid; }
  .banner small { display:block; font-size:13px; font-weight:500; margin-top:6px; }
  .banner.red   { background:var(--redbg);   color:var(--red);   border-color:var(--red); }
  .banner.amber { background:var(--amberbg); color:var(--amber); border-color:var(--amber); }
  section { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px 16px; margin-bottom:12px; }
  section h2 { margin:0 0 10px; font-size:15px; font-weight:600; color:var(--ink);
    padding-bottom:6px; border-bottom:1px solid var(--line); }
  .cards { display:grid; grid-template-columns:repeat(auto-fit, minmax(190px, 1fr)); gap:10px; }
  .card { background:#fafbfc; border:1px solid var(--line); border-radius:6px; padding:10px 12px; }
  .card .k { color:var(--muted); font-size:11px; text-transform:uppercase; letter-spacing:0.04em; }
  .card .v { font-size:16px; font-weight:600; margin-top:2px; word-break:break-word; }
  .card.warn .v { color:var(--amber); }
  .card.bad  .v { color:var(--red); }
  .card.good .v { color:var(--green); }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th, td { text-align:left; padding:6px 8px; border-bottom:1px solid var(--line); vertical-align:top; }
  th { background:#f7f9fb; font-weight:600; color:var(--muted); font-size:11px; text-transform:uppercase; letter-spacing:0.03em; }
  tr:last-child td { border-bottom:none; }
  tr.error   td { background:#fdecec; }
  tr.warning td { background:#fff7df; }
  .mono { font-family:var(--mono); font-size:12px; }
  details { border:1px solid var(--line); border-radius:6px; margin-bottom:6px; background:#fbfcfd; }
  details > summary { cursor:pointer; padding:8px 12px; font-weight:600; list-style:none;
    display:flex; justify-content:space-between; gap:8px; align-items:center; }
  details > summary::after { content:'+'; font-weight:700; color:var(--muted); }
  details[open] > summary::after { content:'-'; }
  details > summary .tag { font-size:11px; padding:2px 8px; border-radius:10px; font-weight:600; }
  .tag.ok    { background:var(--greenbg); color:var(--green); }
  .tag.err   { background:var(--redbg);   color:var(--red); }
  .tag.warn  { background:var(--amberbg); color:var(--amber); }
  .tag.skip  { background:#eceff3;        color:var(--muted); }
  details .body { padding:0 12px 10px; }
  .muted { color:var(--muted); }
  .mini  { font-size:11px; color:var(--muted); }
  .bar { position:relative; background:#eceff3; border-radius:4px; height:8px; overflow:hidden; min-width:80px; }
  .bar > span { display:block; height:100%; background:var(--accent); }
  .bar.warn > span { background:#d4a021; }
  .bar.bad  > span { background:var(--red); }
  footer { color:var(--muted); font-size:11px; text-align:center; padding:10px 0 20px; }
  @media print {
    body { background:#fff; }
    section, .card { box-shadow:none; }
    details { break-inside: avoid; }
  }
</style>
</head>
<body>
<div class="wrap">
<header>
  <div>
    <h1>Client Check Report</h1>
    <div class="meta">
      $(HtmlEnc $Device.User) @ <strong>$(HtmlEnc $Device.Hostname)</strong>
      &middot; generated $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
      &middot; $(if ($Elevated) { '<span class="pill admin">ELEVATED</span>' } else { '<span class="pill user">STANDARD USER - advanced logs skipped</span>' })
    </div>
  </div>
  <div class="meta">client-check v$script:Version</div>
</header>
"@)

    if ($bannerLevel -ne 'none') {
        $reasonHtml = ''
        if ($Reboot.Reasons.Count -gt 0) {
            $reasonHtml = '<small>Detected: ' + (HtmlEnc ($Reboot.Reasons -join '; ')) + '</small>'
        } elseif ($bannerLevel -eq 'amber') {
            $reasonHtml = '<small>No pending-reboot flag detected, but uptime exceeds 24 hours.</small>'
        }
        $null = $sb.Append(@"
<div class="banner $bannerLevel">
  ACTION REQUIRED: REBOOT THIS DEVICE
  $reasonHtml
</div>
"@)
    }

    # Summary cards
    $uptimeCardClass = if ($uptimeHours -gt 24) { 'card warn' } elseif ($Reboot.Pending) { 'card bad' } else { 'card good' }
    $rebootCardClass = if ($Reboot.Pending) { 'card bad' } else { 'card good' }
    $ramText  = Format-Bytes $Device.TotalRamBytes
    $uptimeT  = if ($Device.Uptime) { Format-TimeSpan $Device.Uptime } else { 'unknown' }
    $lastBoot = if ($Device.LastBoot) { $Device.LastBoot.ToString('yyyy-MM-dd HH:mm') } else { 'unknown' }
    $mecmLine = if ($Mecm.Installed) { "v$($Mecm.ClientVersion) / $($Mecm.SiteCode)" } else { 'not installed' }

    if ($sysDisk) {
        $sysFreeGB  = [math]::Round($sysDisk.FreeBytes  / 1GB, 1)
        $sysTotalGB = [math]::Round($sysDisk.TotalBytes / 1GB, 1)
        $sysFreeText = "$sysFreeGB GB free"
        $sysFreeSub  = "of $sysTotalGB GB on drive $($sysDisk.Drive)"
        $sysCardClass = if ($sysDisk.FreePct -lt 5) { 'card bad' } elseif ($sysDisk.FreePct -lt 15) { 'card warn' } else { 'card' }
    } else {
        $sysFreeText = 'unknown'
        $sysFreeSub  = ''
        $sysCardClass = 'card'
    }

    $null = $sb.Append(@"
<section>
  <h2>Summary</h2>
  <div class="cards">
    <div class="card"><div class="k">OS</div><div class="v">$(HtmlEnc $Device.OsCaption)</div><div class="mini">build $(HtmlEnc $Device.OsBuild)</div></div>
    <div class="$uptimeCardClass"><div class="k">Uptime</div><div class="v">$uptimeT</div><div class="mini">last boot $lastBoot</div></div>
    <div class="$rebootCardClass"><div class="k">Pending reboot</div><div class="v">$(if ($Reboot.Pending) { 'YES' } else { 'No' })</div></div>
    <div class="card"><div class="k">RAM</div><div class="v">$ramText</div></div>
    <div class="$sysCardClass"><div class="k">System drive</div><div class="v">$sysFreeText</div><div class="mini">$sysFreeSub</div></div>
    <div class="card"><div class="k">MECM client</div><div class="v mono">$(HtmlEnc $mecmLine)</div></div>
  </div>
</section>
"@)

    # Device details
    $installDate = if ($Device.InstallDate) { $Device.InstallDate.ToString('yyyy-MM-dd') } else { 'unknown' }
    $null = $sb.Append(@"
<section>
  <h2>Device</h2>
  <table>
    <tr><th style="width:200px">Hostname</th><td>$(HtmlEnc $Device.Hostname) <span class="mini">($(HtmlEnc $Device.DnsHostName))</span></td></tr>
    <tr><th>User</th><td>$(HtmlEnc $Device.User)</td></tr>
    <tr><th>OS</th><td>$(HtmlEnc $Device.OsCaption) (build $(HtmlEnc $Device.OsBuild), version $(HtmlEnc $Device.OsVersion))</td></tr>
    <tr><th>OS installed</th><td>$installDate</td></tr>
    <tr><th>Manufacturer</th><td>$(HtmlEnc $Device.Manufacturer)</td></tr>
    <tr><th>Model</th><td>$(HtmlEnc $Device.Model)</td></tr>
    <tr><th>Serial</th><td class="mono">$(HtmlEnc $Device.Serial)</td></tr>
    <tr><th>Domain / workgroup</th><td>$(HtmlEnc $Device.DomainOrWG)</td></tr>
    <tr><th>Computer DN (AD)</th><td class="mono">$(if ($Directory.DistinguishedName) { HtmlEnc $Directory.DistinguishedName } else { '<span class="muted">not found</span>' })</td></tr>
    <tr><th>Entra / Azure AD</th><td>Joined: $(if ($Directory.AzureAdJoined) { 'yes' } else { 'no' })$(if ($Directory.TenantName) { ' &middot; tenant ' + (HtmlEnc $Directory.TenantName) })</td></tr>
  </table>
</section>
"@)

    # Disks
    $null = $sb.Append('<section><h2>Disks</h2><table><tr><th>Drive</th><th>Label</th><th>Filesystem</th><th>Free</th><th>Used</th><th>Total</th><th style="width:140px">Usage</th></tr>')
    foreach ($d in $Disks) {
        $usedBytes = $d.TotalBytes - $d.FreeBytes
        $usedPct = if ($d.TotalBytes -gt 0) { 100 - $d.FreePct } else { 0 }
        $barClass = 'bar'
        if ($usedPct -ge 95) { $barClass = 'bar bad' }
        elseif ($usedPct -ge 85) { $barClass = 'bar warn' }
        $null = $sb.Append("<tr><td class='mono'>$(HtmlEnc $d.Drive)</td><td>$(HtmlEnc $d.Label)</td><td>$(HtmlEnc $d.FileSys)</td><td>$(Format-Bytes $d.FreeBytes)</td><td>$(Format-Bytes $usedBytes)</td><td>$(Format-Bytes $d.TotalBytes)</td><td><div class='$barClass'><span style='width:$usedPct%'></span></div></td></tr>")
    }
    $null = $sb.Append('</table></section>')

    # Network
    $null = $sb.Append('<section><h2>Network adapters (up)</h2><table><tr><th>Name</th><th>Description</th><th>MAC</th><th>Link</th><th>IPv4</th><th>IPv6</th><th>Gateway</th><th>DNS</th></tr>')
    foreach ($n in $Network) {
        $null = $sb.Append("<tr><td>$(HtmlEnc $n.Name)</td><td class='mini'>$(HtmlEnc $n.Description)</td><td class='mono'>$(HtmlEnc $n.Mac)</td><td>$(HtmlEnc $n.LinkSpeed)</td><td class='mono'>$(HtmlEnc $n.Ipv4)</td><td class='mono'>$(HtmlEnc $n.Ipv6)</td><td class='mono'>$(HtmlEnc $n.Gateway)</td><td class='mono'>$(HtmlEnc $n.Dns)</td></tr>")
    }
    if (-not $Network -or $Network.Count -eq 0) {
        $null = $sb.Append('<tr><td colspan="8" class="muted">no adapters up</td></tr>')
    }
    $null = $sb.Append('</table></section>')

    # Group Policy / Registry.pol
    $null = $sb.Append('<section><h2>Group Policy (Registry.pol)</h2><table><tr><th>Scope</th><th>Path</th><th>Size</th><th>Modified</th><th>Header</th><th>Status</th></tr>')
    foreach ($p in $Pol) {
        $rowClass = if (-not $p.Healthy) { 'error' } else { '' }
        $statusText = if ($p.Healthy) { '<span style="color:var(--green)">ok</span>' } else { '<span style="color:var(--red)">check</span>' }
        $size = if ($p.Exists) { "$($p.Size) B" } else { '-' }
        $mod  = if ($p.Modified) { $p.Modified.ToString('yyyy-MM-dd HH:mm') } else { '-' }
        $note = if ($p.Note) { "<div class='mini'>$(HtmlEnc $p.Note)</div>" } else { '' }
        $null = $sb.Append("<tr class='$rowClass'><td>$(HtmlEnc $p.Scope)</td><td class='mono mini'>$(HtmlEnc $p.Path)</td><td>$size</td><td>$mod</td><td class='mono'>$(HtmlEnc $p.Header)</td><td>$statusText$note</td></tr>")
    }
    $null = $sb.Append('</table></section>')

    # MECM client
    $null = $sb.Append('<section><h2>MECM client</h2>')
    if (-not $Mecm.Installed) {
        $null = $sb.Append('<p class="muted">MECM client not detected on this device.</p>')
    } else {
        $lastPolicy = if ($Mecm.LastPolicyEval) { $Mecm.LastPolicyEval.ToString('yyyy-MM-dd HH:mm') } else { 'unknown' }
        $lastHw     = if ($Mecm.LastHwInv)      { $Mecm.LastHwInv.ToString('yyyy-MM-dd HH:mm') }      else { 'unknown' }
        $lastSw     = if ($Mecm.LastSwInv)      { $Mecm.LastSwInv.ToString('yyyy-MM-dd HH:mm') }      else { 'unknown' }
        $null = $sb.Append(@"
<table>
  <tr><th style="width:220px">Client version</th><td class="mono">$(HtmlEnc $Mecm.ClientVersion)</td></tr>
  <tr><th>Site code</th><td class="mono">$(HtmlEnc $Mecm.SiteCode)</td></tr>
  <tr><th>Management point</th><td class="mono">$(HtmlEnc $Mecm.ManagementPoint)</td></tr>
  <tr><th>Last policy evaluation</th><td>$lastPolicy</td></tr>
  <tr><th>Last hardware inventory</th><td>$lastHw</td></tr>
  <tr><th>Last software inventory</th><td>$lastSw</td></tr>
  <tr><th>Cache size (configured)</th><td>$($Mecm.CacheSize) MB</td></tr>
  <tr><th>Log path</th><td class="mono">$(HtmlEnc $Mecm.LogPath)</td></tr>
</table>
"@)
    }
    $null = $sb.Append('</section>')

    # MECM client logs - errors and warnings (last $HoursBack hours)
    $null = $sb.Append("<section><h2>MECM client logs (last $HoursBack h): errors and warnings</h2>")
    $anyErr = ($Logs | Where-Object { $_.Readable -and ($_.Entries | Where-Object Type -eq 3).Count -gt 0 } | Measure-Object).Count
    $anyWarn = ($Logs | Where-Object { $_.Readable -and ($_.Entries | Where-Object Type -eq 2).Count -gt 0 } | Measure-Object).Count
    if ($anyErr -eq 0 -and $anyWarn -eq 0) {
        $null = $sb.Append("<p class='muted'>No errors or warnings in the last $HoursBack hours across monitored MECM client logs.</p>")
    }
    foreach ($l in $Logs) {
        if (-not $l.Found) {
            $null = $sb.Append("<details><summary><span>$(HtmlEnc $l.Name)</span><span class='tag skip'>not present</span></summary><div class='body'><p class='muted mini'>Log file not found (checked .log and .lo_).</p></div></details>")
            continue
        }
        if (-not $l.Readable) {
            $null = $sb.Append("<details><summary><span>$(HtmlEnc $l.Name)</span><span class='tag skip'>unreadable</span></summary><div class='body'><p class='mini'>$(HtmlEnc $l.ReadError)</p></div></details>")
            continue
        }

        $errCount = ($l.Entries | Where-Object Type -eq 3 | Measure-Object).Count
        $warnCount = ($l.Entries | Where-Object Type -eq 2 | Measure-Object).Count

        if ($l.Entries.Count -eq 0) {
            $olderNote = if ($l.CountTotal -gt 0) { "<p class='muted mini'>$($l.CountTotal) older entries in file (outside the $HoursBack h window).</p>" } else { "<p class='muted mini'>No errors or warnings in file.</p>" }
            $tagText = if ($l.CountTotal -gt 0) { "clean in window ($($l.CountTotal) older)" } else { 'clean' }
            $null = $sb.Append("<details><summary><span>$(HtmlEnc $l.Name)</span><span class='tag ok'>$tagText</span></summary><div class='body'>$olderNote</div></details>")
            continue
        }

        $tagClass = if ($errCount -gt 0) { 'tag err' } else { 'tag warn' }
        $bits = @()
        if ($errCount -gt 0)  { $bits += "$errCount error(s)" }
        if ($warnCount -gt 0) { $bits += "$warnCount warning(s)" }
        $tagText = $bits -join ', '
        $null = $sb.Append("<details open><summary><span>$(HtmlEnc $l.Name)</span><span class='$tagClass'>$tagText</span></summary><div class='body'><table><tr><th style='width:155px'>Time</th><th style='width:80px'>Level</th><th style='width:170px'>Component</th><th>Message</th></tr>")
        foreach ($e in $l.Entries) {
            $rowCls = if ($e.Type -eq 3) { 'error' } else { 'warning' }
            $t = if ($e.Timestamp) { $e.Timestamp.ToString('yyyy-MM-dd HH:mm:ss') } else { '-' }
            $null = $sb.Append("<tr class='$rowCls'><td class='mono mini'>$t</td><td>$(HtmlEnc $e.Level)</td><td class='mono mini'>$(HtmlEnc $e.Component)</td><td class='mini'>$(HtmlEnc $e.Message)</td></tr>")
        }
        $null = $sb.Append('</table></div></details>')
    }
    $null = $sb.Append('</section>')

    # Windows event log
    $null = $sb.Append("<section><h2>Windows event log (last $HoursBack h)</h2>")
    if ($EventLog.Skipped) {
        $null = $sb.Append('<p class="muted">Skipped: Get-WinEvent on Application/System logs requires elevation. Re-run client-check as administrator to include this section.</p>')
    } else {
        if (-not $EventLog.Events -or $EventLog.Events.Count -eq 0) {
            $null = $sb.Append('<p class="muted">No Critical/Error/Warning events in the last 24 hours.</p>')
        } else {
            $null = $sb.Append('<table><tr><th style="width:150px">Time</th><th>Log</th><th>Level</th><th>Source</th><th>ID</th><th>Message</th></tr>')
            foreach ($e in $EventLog.Events) {
                $rowClass = switch ($e.Level) { 'Error' {'error'} 'Critical' {'error'} 'Warning' {'warning'} default {''} }
                $msg = if ($e.Message.Length -gt 260) { $e.Message.Substring(0,260) + '...' } else { $e.Message }
                $null = $sb.Append("<tr class='$rowClass'><td class='mono mini'>$($e.Time.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$(HtmlEnc $e.Log)</td><td>$(HtmlEnc $e.Level)</td><td class='mini'>$(HtmlEnc $e.Provider)</td><td class='mono'>$($e.Id)</td><td class='mini'>$(HtmlEnc $msg)</td></tr>")
            }
            $null = $sb.Append('</table>')
        }
    }
    $null = $sb.Append('</section>')

    # Installed applications
    $null = $sb.Append("<section><h2>Installed applications ($($Apps.Count))</h2><details><summary><span>Full list</span><span class='tag'>$($Apps.Count) apps</span></summary><div class='body'><table><tr><th>Name</th><th>Version</th><th>Publisher</th><th>Installed</th><th>Scope</th></tr>")
    foreach ($a in $Apps) {
        $null = $sb.Append("<tr><td>$(HtmlEnc $a.Name)</td><td class='mono mini'>$(HtmlEnc $a.Version)</td><td class='mini'>$(HtmlEnc $a.Publisher)</td><td class='mono mini'>$(HtmlEnc $a.Installed)</td><td>$(HtmlEnc $a.Scope)</td></tr>")
    }
    $null = $sb.Append('</table></div></details></section>')

    $elapsed = [math]::Round(((Get-Date) - $script:Start).TotalSeconds, 1)
    $null = $sb.Append(@"
<footer>
  client-check v$script:Version &middot; generated in ${elapsed}s &middot; self-contained: share this file with support as-is
</footer>
</div>
</body>
</html>
"@)

    $sb.ToString()
}

# --- orchestration ---------------------------------------------------------

if (-not (Test-Path -LiteralPath $OutputDir)) {
    $null = New-Item -ItemType Directory -Path $OutputDir -Force
}

$elevated = Test-Elevated
$since    = (Get-Date).AddHours(-$HoursBack)
Write-Verbose "Elevated: $elevated"
Write-Host "client-check v$script:Version starting ($(if($elevated){'elevated'}else{'standard user'}), $HoursBack h window)..."

Write-Host "  gathering device summary..."
$device    = Get-DeviceSummary
Write-Host "  checking pending reboot..."
$reboot    = Get-RebootStatus
Write-Host "  enumerating disks..."
$disks     = @(Get-DiskInfo)
Write-Host "  enumerating network..."
$network   = @(Get-NetworkInfo)
Write-Host "  querying directory / ADOU..."
$directory = Get-DirectoryJoinInfo
Write-Host "  checking Registry.pol health..."
$pol       = @(Get-RegistryPolStatus)
Write-Host "  enumerating installed applications..."
$apps      = @(Get-InstalledApps)
Write-Host "  querying MECM client..."
$mecm      = Get-MecmClientInfo
Write-Host "  scanning MECM client logs (errors + warnings, last $HoursBack h)..."
$logs      = @(Get-MecmLogSet -LogRoot $mecm.LogPath -Since $since)
Write-Host "  querying Windows event log..."
$evt       = Get-EventLogErrors -Hours $HoursBack

Write-Host "  rendering HTML..."
$html = New-HtmlReport -Device $device -Reboot $reboot -Disks $disks -Network $network `
    -Directory $directory -Pol $pol -Apps $apps -Mecm $mecm -Logs $logs -EventLog $evt -Elevated $elevated -HoursBack $HoursBack

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$fname = "$($env:USERNAME)_$($env:COMPUTERNAME)_$stamp.html"
$out   = Join-Path $OutputDir $fname

[System.IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding($false)))

$size = (Get-Item $out).Length
Write-Host ""
Write-Host "Report written: $out ($([math]::Round($size/1KB,1)) KB)" -ForegroundColor Green

if (-not $NoLaunch) {
    try {
        Start-Process msedge.exe -ArgumentList "`"$out`""
    } catch {
        Start-Process $out
    }
}
