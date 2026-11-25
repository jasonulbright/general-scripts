# CI-CB

Builders for ConfigMgr Configuration Items (CI) and Configuration Baselines (CB). Each control has its own folder, grouped by category.

A control folder holds:

- `New-*.ps1`: the builder. It creates the CI and the baseline, and can deploy the baseline to a collection.
- `metadata.psd1`: a description of the control (registry surface, OS scope, builder parameters, objects created).
- `README.md`: what the control does and how to run it.

Most builders use native registry settings, so ConfigMgr does the discovery, comparison and remediation. They take `-SiteCode`, `-SiteServer`, an optional `-CollectionName`, and (where it applies) `-DetectOnly`. Run them from a computer with the ConfigMgr console installed. The target collections can come from the scripts in [`../Collections/`](../Collections/).

## Categories

| Folder | Purpose | Controls |
|--------|---------|----------|
| [`Compliance/`](Compliance/) | Settings that a compliance review expects. | 7 |
| [`Configuration/`](Configuration/) | Configuration enforcement and product workarounds. | 2 |
| [`CVE-Remediation/`](CVE-Remediation/) | Mitigations for named CVEs. | 1 |
| [`Hardening/`](Hardening/) | Credential and network hardening. | 6 |
| [`Maintenance/`](Maintenance/) | Scheduled cleanup of data on clients. | 1 |
