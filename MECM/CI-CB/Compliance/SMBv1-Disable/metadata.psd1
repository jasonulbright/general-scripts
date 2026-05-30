@{
    # === Identity ===
    Id          = 'smbv1-disable'
    Version     = '1.0.0'
    DisplayName = 'SMBv1 Disable (server)'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Disables the SMBv1 server protocol via LanmanServer\Parameters\SMB1 = 0. Server-side scope; the SMBv1 client redirector is Windows-feature-removed on supported OSes. Single DWORD enforcement.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @(96982)
    KbReferences   = @()

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
            KeyPath = 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
            Values  = @('SMB1')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-SMBv1DisableBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';       Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'SiteServer';     Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site server FQDN.' }
            @{ Name = 'CollectionName'; Type = 'String'; Required = $false; Default = $null;  Description = 'If specified, deploys the baseline to this collection daily.' }
            @{ Name = 'DetectOnly';     Type = 'Switch'; Required = $false; Default = $false; Description = 'Create with remediation disabled.' }
        )
    }

    # === Dependencies ===
    DependsOn = @()

    # === MECM artifacts produced ===
    Produces = @{
        ConfigurationItems     = @('Compliance: SMBv1 Disable')
        ConfigurationBaselines = @('Compliance SMBv1 Disable')
    }
}
