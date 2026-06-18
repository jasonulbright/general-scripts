@{
    # === Identity ===
    Id          = 'lsa-protection-runasppl'
    Version     = '1.0.0'
    DisplayName = 'LSA Protection (RunAsPPL)'
    Subcategory = 'Hardening'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Enables LSA Protection (RunAsPPL = 1) so LSASS runs as a Protected Process Light, blocking most credential-dumping tooling. High-value, low-cost, almost always missed. REBOOT REQUIRED to engage; validate LSA plugin signing first.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection')

    # === Scope ===
    OsScope = @{
        Client = @('Windows 8.1', 'Windows 10', 'Windows 11')
        Server = @('Server 2012 R2', 'Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $true

    # === Reg surface ===
    RegistrySurface = @(
        @{
            Hive    = 'HKLM'
            KeyPath = 'SYSTEM\CurrentControlSet\Control\Lsa'
            Values  = @('RunAsPPL')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-LSAProtectionBaseline.ps1'
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
        ConfigurationItems     = @('Hardening: LSA Protection (RunAsPPL)')
        ConfigurationBaselines = @('Hardening LSA Protection RunAsPPL')
    }
}
