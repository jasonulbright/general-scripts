@{
    # === Identity ===
    Id          = 'uac-remote-restriction'
    Version     = '1.0.0'
    DisplayName = 'UAC Remote Restriction (LocalAccountTokenFilterPolicy)'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Keeps UAC remote token filtering enabled (LocalAccountTokenFilterPolicy = 0). Blocks Pass-the-Hash / lateral movement via local admin accounts over the network. Often silently set to 1 by old remote-admin guides and never re-audited. Single DWORD; no reboot.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/troubleshoot/windows-server/windows-security/user-account-control-and-remote-restriction')

    # === Scope ===
    OsScope = @{
        Client = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows 11')
        Server = @('Server 2008 R2', 'Server 2012', 'Server 2012 R2', 'Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $false

    # === Reg surface ===
    RegistrySurface = @(
        @{
            Hive    = 'HKLM'
            KeyPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            Values  = @('LocalAccountTokenFilterPolicy')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-UACRemoteRestrictionBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';       Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'SiteServer';     Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site server FQDN.' }
            @{ Name = 'CollectionName'; Type = 'String'; Required = $false; Default = $null;  Description = 'If specified, deploys the baseline to this collection daily.' }
            @{ Name = 'DetectOnly';     Type = 'Switch'; Required = $false; Default = $false; Description = 'Create / deploy without remediation.' }
        )
    }

    # === Dependencies ===
    DependsOn = @()

    # === MECM artifacts produced ===
    Produces = @{
        ConfigurationItems     = @('Compliance: UAC Remote Restriction (LocalAccountTokenFilterPolicy)')
        ConfigurationBaselines = @('Compliance UAC Remote Restriction')
    }
}
