@{
    # === Identity ===
    Id          = 'wdigest-disable'
    Version     = '1.0.0'
    DisplayName = 'WDigest Credential Caching Disable'
    Subcategory = 'Hardening'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Disables WDigest plaintext credential caching (UseLogonCredential = 0). Blocks Mimikatz sekurlsa::wdigest cleartext credential recovery from LSASS. Frequently missed because modern Windows defaults to safe but rarely pins the value. Single DWORD; no reboot.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/troubleshoot/windows-server/windows-security/credentials-protection-management')

    # === Scope ===
    OsScope = @{
        Client = @('Windows 8.1', 'Windows 10', 'Windows 11')
        Server = @('Server 2012 R2', 'Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $false

    # === Reg surface ===
    RegistrySurface = @(
        @{
            Hive    = 'HKLM'
            KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
            Values  = @('UseLogonCredential')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-WDigestDisableBaseline.ps1'
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
        ConfigurationItems     = @('Hardening: WDigest Credential Caching Disable')
        ConfigurationBaselines = @('Hardening WDigest Credential Caching Disable')
    }
}
