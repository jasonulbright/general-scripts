@{
    # === Identity ===
    Id          = 'anonymous-enumeration-restrict'
    Version     = '1.0.0'
    DisplayName = 'Anonymous Enumeration Restrictions'
    Subcategory = 'Hardening'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Restricts anonymous / null-session enumeration of accounts, groups, and shares (RestrictAnonymous=1, RestrictAnonymousSAM=1, EveryoneIncludesAnonymous=0). Blocks unauthenticated recon for spraying / lateral movement. Silent exposure, easy to miss. Three DWORDs; no reboot.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/network-access-do-not-allow-anonymous-enumeration-of-sam-accounts-and-shares')

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
            KeyPath = 'SYSTEM\CurrentControlSet\Control\Lsa'
            Values  = @('RestrictAnonymous', 'RestrictAnonymousSAM', 'EveryoneIncludesAnonymous')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-AnonymousEnumerationBaseline.ps1'
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
        ConfigurationItems     = @('Hardening: Anonymous Enumeration Restrictions')
        ConfigurationBaselines = @('Hardening Anonymous Enumeration Restrictions')
    }
}
