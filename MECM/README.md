# MECM

Scripts for Microsoft Configuration Manager (ConfigMgr). The folder is named `MECM` for historic reasons. Most scripts need the ConfigMgr console, which provides the `ConfigurationManager` PowerShell module.

## Subfolders

| Folder | Purpose |
|--------|---------|
| [`Applications/`](Applications/) | Creators for ConfigMgr applications. Today: `SpecExec/`, six speculative-execution remediation applications. |
| [`CI-CB/`](CI-CB/) | Builders for Configuration Items and Configuration Baselines, grouped by category (Compliance, Configuration, CVE-Remediation, Hardening, Maintenance). |
| [`Collections/`](Collections/) | Creators for device collections that are built from hardware-inventory queries. |
| [`Scanner-Inventory/`](Scanner-Inventory/) | Inventory of connected scanners with ConfigMgr Run Scripts and CMPivot. |
| [`WinPE/`](WinPE/) | WinPE and operating system deployment helpers. Today: `OSD-ComputerSetup/`. |
| [`WinReset/`](WinReset/) | Zero-touch remote factory reset with automatic domain rejoin. |
| [`cachebaseline/`](cachebaseline/) | Baseline that clears non-persistent client cache content on a schedule. |
| [`client-check/`](client-check/) | Self-service diagnostic that writes an HTML client health report. |

## Scripts in this folder

| File | Purpose |
|------|---------|
| `Export-MECMCredential.ps1` | Generates AES-encrypted credential files (`mecm.key`, `mecm.user`, `mecm.pass`) for `OSD-ComputerSetup.ps1` during WinPE imaging. Run it once on an admin workstation. |
| `Set-MECMManagementPoint.ps1` | Forces ConfigMgr clients to use one management point. It cleans the cached management point references in the registry, WMI and the client data stores, then restarts `CCMExec`. Supports a batch run over PowerShell remoting. |
| `deploy-allapps.ps1` | Creates a Required Install deployment for every application on a target collection. Lab and first-pass helper. Refuses broad collections. |
| `deploy-undeployedapps.ps1` | Creates a Required Install deployment only for applications that have no deployment anywhere. Safe to run again. |
| `distribute-allcontent.ps1` | Distributes the content of every application to a distribution point group. Optional `-NamePattern` filter. "Already targeted" is not an error. |
| `remove-allapps.ps1` | Removes every application in the site. Refuses to run while any application still has a deployment. |
| `remove-alldeployments.ps1` | Removes every application deployment in the site, on all collections. Destructive. For lab resets. |
| `remove-appdeployments.ps1` | Removes all deployments of one application, after a review and a confirmation. |
| `remove-deploymentsbypattern.ps1` | Removes every deployment of pattern-matched applications on one collection. Creates nothing new. |
| `set-availabledeployment.ps1` | Switches pattern-matched applications from any existing deployment to an Available deployment on a collection. |
| `switch-deploymentstouninstall.ps1` | Converts every Install deployment on a collection to an Uninstall deployment. `-KeepInstalledPattern` keeps system dependencies such as runtimes. |

The `remove-*`, `switch-*` and `set-*` scripts change a site. Run them on a lab site first.
