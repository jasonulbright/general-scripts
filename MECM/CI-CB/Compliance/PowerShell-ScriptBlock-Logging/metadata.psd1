@{
    # === Identity ===
    Id          = 'powershell-scriptblock-logging'
    Version     = '1.0.0'
    DisplayName = 'PowerShell Script Block Logging'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Enables PowerShell Script Block Logging (EnableScriptBlockLogging = 1) for detection/forensics (event 4104). The most useful PowerShell detective control; absent from most homegrown baselines because its absence is invisible until you need the logs. Detective only, safe to enable broadly. Single DWORD; no reboot.'
    Severity    = 'Warning'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_logging_windows')

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
            KeyPath = 'SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
            Values  = @('EnableScriptBlockLogging')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-ScriptBlockLoggingBaseline.ps1'
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
        ConfigurationItems     = @('Compliance: PowerShell Script Block Logging')
        ConfigurationBaselines = @('Compliance PowerShell Script Block Logging')
    }
}
