# CCM Cache Cleanup - Remediation Script
# Deletes all non-persistent cache elements.
# Content with "Persist in client cache" flag (0x200) is never removed.
# Uses DeleteCacheElement (not DeleteCacheElementEx) to skip content currently in use.
$CMObject = New-Object -ComObject UIResource.UIResourceMgr
$Cache = $CMObject.GetCacheInfo()
$Cache.GetCacheElements() | Where-Object { -not ($_.ContentFlags -band 0x200) } | ForEach-Object {
    $Cache.DeleteCacheElement($_.CacheElementID)
}
