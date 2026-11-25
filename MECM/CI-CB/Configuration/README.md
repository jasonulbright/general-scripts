# Configuration

Baselines that enforce a configuration value or apply a product workaround. Each folder is one control. Open its README for the details.

## Contents

| Folder | What it enforces | Builder |
|--------|------------------|---------|
| [`Acrobat-AllToolsPane-Fix/`](Acrobat-AllToolsPane-Fix/) | Temporary Adobe workaround for the Acrobat bug where the All Tools pane disappears on Edit PDF (`FeatureLockDown\bGenCoverPagesLabelStrings = 1`). Retire it when Adobe ships the patch. | `New-AcrobatAllToolsPaneFixBaseline.ps1` |
| [`DeliveryOptimization-DownloadMode/`](DeliveryOptimization-DownloadMode/) | Delivery Optimization `DODownloadMode` for each OS class: clients 0 (HTTP, no peering), servers 99 (HTTP, no peering, no cloud service). One CI and baseline for each class. | `New-DODownloadModeBaseline.ps1` |
