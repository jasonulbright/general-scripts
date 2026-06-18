@{
    # === Identity ===
    Id          = 'do-downloadmode'
    Version     = '1.0.0'
    DisplayName = 'Delivery Optimization Download Mode'
    Subcategory = 'Configuration'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Enforces the Delivery Optimization DODownloadMode policy. Clients = 0 (HTTP only, no peering); servers = 99 (HTTP only, no peering, no DO cloud service). Builds one CI + baseline per OS class, deployed to separate collections. Single DWORD; no reboot.'
    Severity    = 'Warning'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows/client-management/mdm/policy-csp-deliveryoptimization#dodownloadmode')

    # === Scope ===
    OsScope = @{
        Client = @('Windows 10', 'Windows 11')
        Server = @('Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $false

    # === Reg surface ===
    RegistrySurface = @(
        @{
            Hive    = 'HKLM'
            KeyPath = 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
            Values  = @('DODownloadMode')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-DODownloadModeBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';             Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'SiteServer';           Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site server FQDN.' }
            @{ Name = 'ClientCollectionName'; Type = 'String'; Required = $false; Default = $null;  Description = 'Deploy the client baseline (DODownloadMode = 0) to this collection daily.' }
            @{ Name = 'ServerCollectionName'; Type = 'String'; Required = $false; Default = $null;  Description = 'Deploy the server baseline (DODownloadMode = 99) to this collection daily.' }
            @{ Name = 'ClientDownloadMode';   Type = 'String'; Required = $false; Default = '0';    Description = 'Expected DODownloadMode for clients. One of 0,1,2,3,99.' }
            @{ Name = 'ServerDownloadMode';   Type = 'String'; Required = $false; Default = '99';   Description = 'Expected DODownloadMode for servers. One of 0,1,2,3,99.' }
            @{ Name = 'DetectOnly';           Type = 'Switch'; Required = $false; Default = $false; Description = 'Create / deploy without remediation (audit mode).' }
        )
    }

    # === Dependencies ===
    # Needs client-only and server-only collections to deploy against. "All Workstations" /
    # "All Windows Servers" if they exist, else build dedicated ones.
    DependsOn = @()

    # === MECM artifacts produced ===
    Produces = @{
        ConfigurationItems     = @('Delivery Optimization: DODownloadMode (Client)', 'Delivery Optimization: DODownloadMode (Server)')
        ConfigurationBaselines = @('Delivery Optimization DODownloadMode (Client)', 'Delivery Optimization DODownloadMode (Server)')
    }
}
