# CCM Cache Cleanup - Discovery Script
# Returns non-persistent cache size in MB (integer).
# Content with "Persist in client cache" flag (0x200) is excluded from the count.
# MECM CI rule: Value <= 20480 (20GB) = Compliant
$CMObject = New-Object -ComObject UIResource.UIResourceMgr
$Cache = $CMObject.GetCacheInfo()
$NonPersistent = $Cache.GetCacheElements() | Where-Object { -not ($_.ContentFlags -band 0x200) }
$SizeMB = ($NonPersistent | Measure-Object -Property ContentSize -Sum).Sum
if ($null -eq $SizeMB) { $SizeMB = 0 }
[math]::Round($SizeMB / 1024)
