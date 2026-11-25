@{
    # === Identity ===
    Id          = 'user-profile-cleanup'
    Version     = '1.0.0'
    DisplayName = 'User Profile Cleanup'
    Subcategory = 'Maintenance'
    Mechanism   = 'ScriptSetting'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Removes stale user profiles (folder, NTUSER.DAT hive and ProfileList registration) that were not used for N days, plus orphaned ProfileList keys, ProfileGuid keys and profile folders. The day count is asked at creation time and is part of the CI and baseline names. Loaded profiles, the built-in Administrator and system profiles are never touched.'
    Severity    = 'Warning'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @(
        'https://learn.microsoft.com/troubleshoot/windows-server/support-tools/scripts-retrieve-profile-age-delete-aged-copies'
        'https://learn.microsoft.com/troubleshoot/windows-server/support-tools/scripts-to-retrieve-profile-age'
        'https://learn.microsoft.com/troubleshoot/windows-server/support-tools/scripts-to-cleanup-profile-folder-information-and-prevent-temp-user-profiles-from-being-created'
    )

    # === Scope ===
    OsScope = @{
        Client = @('Windows 10', 'Windows 11')
        Server = @('Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $false

    # === Reg surface (read and cleaned by the scripts) ===
    RegistrySurface = @(
        @{
            Hive    = 'HKLM'
            KeyPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
            Values  = @('ProfileImagePath', 'LocalProfileLoadTimeLow', 'LocalProfileLoadTimeHigh', 'LocalProfileUnLoadTimeLow', 'LocalProfileUnLoadTimeHigh', 'LocalProfileCleanupCheckTimeLow', 'LocalProfileCleanupCheckTimeHigh')
        }
        @{
            Hive    = 'HKLM'
            KeyPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid'
            Values  = @('SidString')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-UserProfileCleanupBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';        Type = 'String';   Required = $true;  Default = $null;  Description = 'ConfigMgr site code.' }
            @{ Name = 'SiteServer';      Type = 'String';   Required = $true;  Default = $null;  Description = 'ConfigMgr site server FQDN.' }
            @{ Name = 'Days';            Type = 'Int';      Required = $false; Default = $null;  Description = 'Days of inactivity (1-3650). Asked when omitted.' }
            @{ Name = 'ExcludeAccounts'; Type = 'String[]'; Required = $false; Default = @();   Description = 'Wildcard patterns of accounts to keep.' }
            @{ Name = 'IncludeAccounts'; Type = 'String[]'; Required = $false; Default = @('*'); Description = 'Wildcard patterns of accounts to clean.' }
            @{ Name = 'Scope';           Type = 'String[]'; Required = $false; Default = @('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder'); Description = 'Kinds of item to clean.' }
            @{ Name = 'CollectionName';  Type = 'String';   Required = $false; Default = $null;  Description = 'If specified, deploys the baseline to this collection.' }
            @{ Name = 'ScheduleDays';    Type = 'Int';      Required = $false; Default = 7;      Description = 'Evaluation interval of the deployment in days.' }
            @{ Name = 'DetectOnly';      Type = 'Switch';   Required = $false; Default = $false; Description = 'Report only. No remediation script.' }
            @{ Name = 'ScriptOnly';      Type = 'Switch';   Required = $false; Default = $false; Description = 'Write the CI scripts to OutputFolder and stop.' }
        )
    }

    # === Dependencies ===
    DependsOn = @()

    # === ConfigMgr artifacts produced ({Days} is the day count that is asked at creation time) ===
    Produces = @{
        ConfigurationItems     = @('Maintenance: User Profile Cleanup - {Days} Days')
        ConfigurationBaselines = @('Maintenance User Profile Cleanup - {Days} Days')
        Packages               = @('Maintenance: User Profile Cleanup (Package) - {Days} Days')
        Programs               = @('Clean up user profiles ({Days} days)')
    }

    # === Second builder: package + program (recurring deployment or task sequence step) ===
    PackageBuilder = @{
        ScriptPath = 'New-UserProfileCleanupPackage.ps1'
        Runner     = 'Invoke-UserProfileCleanup.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';                   Type = 'String';   Required = $true;  Default = $null; Description = 'ConfigMgr site code.' }
            @{ Name = 'SiteServer';                 Type = 'String';   Required = $true;  Default = $null; Description = 'ConfigMgr site server FQDN.' }
            @{ Name = 'SourcePath';                 Type = 'String';   Required = $true;  Default = $null; Description = 'Folder (UNC) for the package content.' }
            @{ Name = 'Days';                       Type = 'Int';      Required = $false; Default = $null; Description = 'Days of inactivity (1-3650). Asked when omitted.' }
            @{ Name = 'DistributionPointGroupName'; Type = 'String';   Required = $false; Default = $null; Description = 'Distribution point group for the content.' }
            @{ Name = 'DistributionPointName';      Type = 'String';   Required = $false; Default = $null; Description = 'Distribution point for the content.' }
            @{ Name = 'CollectionName';             Type = 'String';   Required = $false; Default = $null; Description = 'If specified, creates a required recurring deployment.' }
            @{ Name = 'ScheduleDays';               Type = 'Int';      Required = $false; Default = 7;     Description = 'The program runs every this many days.' }
            @{ Name = 'StageOnly';                  Type = 'Switch';   Required = $false; Default = $false; Description = 'Write the content and stop.' }
        )
    }
}
