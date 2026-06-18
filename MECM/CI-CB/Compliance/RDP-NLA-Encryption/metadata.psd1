@{
    # === Identity ===
    Id          = 'rdp-nla-tls-require'
    Version     = '1.0.0'
    DisplayName = 'RDP NLA + TLS Required'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Requires RDP Network Level Authentication (UserAuthentication = 1) and TLS (SecurityLayer = 2). Removes pre-auth RDP attack surface and the legacy RDP Security Layer. Easy to miss because RDP works without them. Two DWORDs; no reboot. Harmless on non-RDP hosts (key exists by default), so deployed fleet-wide.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows-server/remote/remote-desktop-services/clients/remote-desktop-allow-access')

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
            KeyPath = 'SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
            Values  = @('UserAuthentication', 'SecurityLayer')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-RDPHardeningBaseline.ps1'
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
        ConfigurationItems     = @('Compliance: RDP NLA + TLS Required')
        ConfigurationBaselines = @('Compliance RDP NLA TLS Required')
    }
}
