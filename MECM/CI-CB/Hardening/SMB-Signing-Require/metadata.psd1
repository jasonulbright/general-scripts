@{
    # === Identity ===
    Id          = 'smb-signing-require'
    Version     = '1.0.0'
    DisplayName = 'SMB Signing Required'
    Subcategory = 'Hardening'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Requires SMB signing on both the Workstation (client) and Server services (RequireSecuritySignature = 1). Defeats SMB relay / MITM lateral movement. Missed because the default is enabled-but-not-required, which still allows downgrade. Two DWORDs; no reboot. Test legacy SMB peers first.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows-server/storage/file-server/smb-signing-overview')

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
            KeyPath = 'SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
            Values  = @('RequireSecuritySignature')
        }
        @{
            Hive    = 'HKLM'
            KeyPath = 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
            Values  = @('RequireSecuritySignature')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-SMBSigningBaseline.ps1'
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
        ConfigurationItems     = @('Hardening: SMB Signing Required')
        ConfigurationBaselines = @('Hardening SMB Signing Required')
    }
}
