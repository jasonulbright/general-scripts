@{
    # === Identity ===
    Id          = 'llmnr-disable'
    Version     = '1.0.0'
    DisplayName = 'LLMNR Disable'
    Subcategory = 'Hardening'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Disables Link-Local Multicast Name Resolution via the DNSClient policy. Prevents Responder-style name-resolution poisoning attacks. Single DWORD; no reboot required.'
    Severity    = 'Warning'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
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
            KeyPath = 'SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
            Values  = @('EnableMulticast')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-LLMNRDisableBaseline.ps1'
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
        ConfigurationItems     = @('Hardening: LLMNR Disable')
        ConfigurationBaselines = @('Hardening LLMNR Disable')
    }
}
