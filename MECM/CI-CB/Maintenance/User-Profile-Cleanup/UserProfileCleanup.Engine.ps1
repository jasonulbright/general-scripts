# User profile cleanup engine.
#
# This file defines functions only. Dot-source it, then call Get-UserProfileCleanupItem
# and Remove-UserProfileCleanupItem. New-UserProfileCleanupBaseline.ps1 embeds the
# text of this file, without comments, in the ConfigMgr discovery and remediation scripts.
#
# Targets Windows PowerShell 5.1 and PowerShell 7. Runs as an administrator or as SYSTEM.
# Sources: Microsoft Learn pages "Scripts: Retrieve profile age and optionally delete aged
# copies" and "Scripts: Clean up profile folder information and prevent TEMP user profiles
# from being created" (learn.microsoft.com/troubleshoot/windows-server/support-tools).

function ConvertFrom-UserProfileFileTime {
    # .SYNOPSIS
    # Converts the Low and High DWORD halves of a FILETIME registry value to a UTC date.
    #
    # .DESCRIPTION
    # The profile service stores load, unload and cleanup times as two REG_DWORD values.
    # PowerShell returns a DWORD as a signed Int32, so the halves are masked to unsigned
    # 32-bit values before they are joined. A missing value or a zero time returns $null.
    # This function does not throw.
    #
    # .PARAMETER LowPart
    # Low DWORD of the FILETIME. $null when the value is missing.
    #
    # .PARAMETER HighPart
    # High DWORD of the FILETIME. $null when the value is missing.
    #
    # .EXAMPLE
    # $objTime = ConvertFrom-UserProfileFileTime -LowPart -1594323968 -HighPart 31123456
    #
    # # $objTime is a [datetime] in UTC, or $null when the result is zero.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [datetime] The time in UTC, or $null when the value is missing or zero.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([datetime])]
    param (
        [object]$LowPart,
        [object]$HighPart
    )

    if (($null -eq $LowPart) -or ($null -eq $HighPart)) {
        return $null
    }
    $longLow = ([long]$LowPart) -band 0xFFFFFFFFL
    $longHigh = ([long]$HighPart) -band 0xFFFFFFFFL
    $longFileTime = ($longHigh -shl 32) -bor $longLow
    if (($longFileTime -le 0) -or ($longFileTime -gt 2650467743999999999L)) {
        return $null
    }
    return [datetime]::FromFileTimeUtc($longFileTime)
}


function Test-UserProfileAccountMatch {
    # .SYNOPSIS
    # Tests whether an account matches one of a list of wildcard patterns.
    #
    # .DESCRIPTION
    # Each pattern is compared with -like to every candidate name: the SID, the profile
    # folder name, the account name and the DOMAIN\name form. Matching is case-insensitive.
    # An empty pattern list never matches.
    #
    # .PARAMETER Pattern
    # Wildcard patterns, for example 'svc_*', 'CONTOSO\*' or an exact SID.
    #
    # .PARAMETER Candidate
    # Names to test. Empty and $null entries are skipped.
    #
    # .EXAMPLE
    # Test-UserProfileAccountMatch -Pattern 'svc_*' -Candidate @('S-1-5-21-1', 'svc_backup')
    #
    # # Returns $true.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [bool] $true when any candidate matches any pattern; otherwise $false.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [string[]]$Pattern = @(),
        [string[]]$Candidate = @()
    )

    foreach ($strPattern in @($Pattern)) {
        if ([string]::IsNullOrWhiteSpace($strPattern)) {
            continue
        }
        foreach ($strCandidate in @($Candidate)) {
            if ([string]::IsNullOrEmpty($strCandidate)) {
                continue
            }
            if ($strCandidate -like $strPattern) {
                return $true
            }
        }
    }
    return $false
}


function ConvertTo-SingleQuotedLiteral {
    # .SYNOPSIS
    # Returns a string as a PowerShell single-quoted literal.
    #
    # .DESCRIPTION
    # Doubles each single quote. Throws when the text has a character outside printable
    # ASCII (control characters, and typographic quotes that PowerShell also reads as quote
    # characters), or when it is not a valid wildcard pattern. The value is written into a
    # script that runs on every client, so a bad value is stopped here.
    #
    # .PARAMETER Text
    # The text to quote.
    #
    # .EXAMPLE
    # ConvertTo-SingleQuotedLiteral -Text "O'Brien*"
    #
    # # Returns 'O''Brien*' including the outer quotes.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The quoted literal.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($Text -notmatch '^[\x20-\x7E]*$') {
        throw 'A pattern has a character that is not printable ASCII.'
    }
    try {
        [void]('x' -like $Text)
    } catch {
        Write-Debug ("Wildcard test failed: {0}" -f $_.Exception.Message)
        throw ("The pattern '{0}' is not a valid wildcard pattern: {1}" -f $Text, $_.Exception.Message)
    }
    if ($Text.Length -gt 256) {
        throw 'A pattern is longer than 256 characters.'
    }
    return ("'" + $Text.Replace("'", "''") + "'")
}


function ConvertTo-SingleQuotedArray {
    # .SYNOPSIS
    # Returns a list of strings as a PowerShell array literal.
    #
    # .DESCRIPTION
    # Each element is quoted with ConvertTo-SingleQuotedLiteral. An empty list returns @().
    #
    # .PARAMETER Value
    # The strings.
    #
    # .EXAMPLE
    # ConvertTo-SingleQuotedArray -Value @('a', 'b')
    #
    # # Returns @('a', 'b')
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The array literal.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string[]]$Value = @()
    )

    $arrQuoted = @()
    foreach ($strValue in @($Value)) {
        if ([string]::IsNullOrWhiteSpace($strValue)) {
            continue
        }
        $arrQuoted += ConvertTo-SingleQuotedLiteral -Text $strValue
    }
    return ('@(' + ($arrQuoted -join ', ') + ')')
}


function Read-InactivityDayCount {
    # .SYNOPSIS
    # Asks the operator for the day count until a valid number is entered.
    #
    # .DESCRIPTION
    # Accepts a whole number from 1 to 3650. Throws when the host cannot prompt.
    #
    # .EXAMPLE
    # $intDays = Read-InactivityDayCount
    #
    # # Prompts, then returns 90 when the operator types 90.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [int] The day count.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([int])]
    param ()

    while ($true) {
        try {
            $strAnswer = Read-Host -Prompt 'Days a user profile must be unused before it is cleaned up (for example 30, 60, 90)'
        } catch {
            Write-Debug ("Prompt failed: {0}" -f $_.Exception.Message)
            throw 'The day count was not given and the host cannot prompt. Pass -Days.'
        }
        $intDays = 0
        if ([int]::TryParse(([string]$strAnswer).Trim(), [ref]$intDays) -and ($intDays -ge 1) -and ($intDays -le 3650)) {
            return $intDays
        }
        Write-Warning 'Enter a whole number from 1 to 3650.'
    }
}


function Resolve-UserProfileAccountName {
    # .SYNOPSIS
    # Resolves a SID to a DOMAIN\name account string.
    #
    # .DESCRIPTION
    # Returns the SID text when the account cannot be resolved, for example when the
    # account was deleted from Active Directory. This function does not throw.
    #
    # .PARAMETER Sid
    # The security identifier in string form.
    #
    # .EXAMPLE
    # Resolve-UserProfileAccountName -Sid 'S-1-5-21-1-2-3-1001'
    #
    # # Returns 'CONTOSO\jdoe', or the SID when no account exists.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The account name, or the SID.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Sid
    )

    try {
        $objSecurityIdentifier = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList $Sid
        $objAccount = $objSecurityIdentifier.Translate([System.Security.Principal.NTAccount])
        return [string]$objAccount.Value
    } catch {
        Write-Debug ("Account name for '{0}' did not resolve: {1}" -f $Sid, $_.Exception.Message)
        return $Sid
    }
}


function Write-UserProfileCleanupLog {
    # .SYNOPSIS
    # Appends one line to the cleanup log file.
    #
    # .DESCRIPTION
    # Creates the folder when it is missing. When the file is larger than 1 MB it is
    # renamed to the same name with a .lo_ extension, as the ConfigMgr client does. A log
    # failure never stops the cleanup: the function writes a debug message and returns.
    #
    # .PARAMETER LogPath
    # Full path of the log file. An empty value turns logging off.
    #
    # .PARAMETER Level
    # INFO, WARN or ERROR.
    #
    # .PARAMETER Message
    # The text of the line.
    #
    # .EXAMPLE
    # Write-UserProfileCleanupLog -LogPath 'C:\Windows\CCM\Logs\UserProfileCleanup.log' -Level INFO -Message 'Started'
    #
    # # Appends "2026-11-25 10:00:00.000  INFO   Started" to the file.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # None.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [string]$LogPath,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }
    try {
        $strFolder = [System.IO.Path]::GetDirectoryName($LogPath)
        if (-not [System.IO.Directory]::Exists($strFolder)) {
            [void][System.IO.Directory]::CreateDirectory($strFolder)
        }
        if ([System.IO.File]::Exists($LogPath)) {
            $objLogFile = New-Object -TypeName System.IO.FileInfo -ArgumentList $LogPath
            if ($objLogFile.Length -gt 1048576) {
                $strRolled = [System.IO.Path]::ChangeExtension($LogPath, '.lo_')
                if ([System.IO.File]::Exists($strRolled)) {
                    [System.IO.File]::Delete($strRolled)
                }
                [System.IO.File]::Move($LogPath, $strRolled)
            }
        }
        $strLine = '{0}  {1,-5}  {2}{3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message, [Environment]::NewLine
        [System.IO.File]::AppendAllText($LogPath, $strLine, [System.Text.Encoding]::ASCII)
    } catch {
        Write-Debug ("Log write failed for '{0}': {1}" -f $LogPath, $_.Exception.Message)
    }
}


function Remove-UserProfileFolderTree {
    # .SYNOPSIS
    # Deletes a profile folder without following junctions or symbolic links.
    #
    # .DESCRIPTION
    # A profile holds junctions such as 'Application Data' and 'Local Settings'. A
    # recursive delete that follows a link deletes the data of the link target. This
    # function walks the tree first and removes each junction and symbolic link as a
    # link, without opening its target. It then deletes the remaining tree with
    # Remove-Item. The extended-length prefix (\\?\) is used so that deep paths work.
    # Reparse points of other kinds, for example OneDrive placeholders, are not links
    # and are deleted as normal content.
    #
    # .PARAMETER Path
    # Full path of the folder to delete.
    #
    # .EXAMPLE
    # Remove-UserProfileFolderTree -Path 'C:\Users\olduser'
    #
    # # The folder and its contents are deleted. Link targets are untouched.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # None. Throws when the folder cannot be deleted.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Set-StrictMode -Version Latest
    $strExtendedPath = $Path
    if (-not $strExtendedPath.StartsWith('\\?\')) {
        $strExtendedPath = '\\?\' + $strExtendedPath
    }
    $stackFolder = New-Object -TypeName 'System.Collections.Generic.Stack[string]'
    $stackFolder.Push($strExtendedPath)
    while ($stackFolder.Count -gt 0) {
        $strFolder = $stackFolder.Pop()
        foreach ($strChild in [System.IO.Directory]::EnumerateDirectories($strFolder)) {
            $objAttributes = [System.IO.File]::GetAttributes($strChild)
            if (($objAttributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                $stackFolder.Push($strChild)
                continue
            }
            $strLinkType = $null
            try {
                $strLinkType = (Get-Item -LiteralPath $strChild -Force -ErrorAction Stop).LinkType
            } catch {
                # Access to the link is denied. A reparse point that cannot be inspected is
                # treated as a link, so its target is never opened.
                Write-Debug ("Link type of '{0}' is unknown: {1}" -f $strChild, $_.Exception.Message)
                $strLinkType = 'Unknown'
            }
            if ([string]::IsNullOrEmpty($strLinkType)) {
                $stackFolder.Push($strChild)
            } else {
                [System.IO.Directory]::Delete($strChild)
            }
        }
    }
    Remove-Item -LiteralPath $strExtendedPath -Recurse -Force -ErrorAction Stop
}


function Test-UserProfileSidAllowed {
    # .SYNOPSIS
    # Tests whether a SID may belong to a profile that this engine cleans.
    #
    # .DESCRIPTION
    # Allowed are local and domain user SIDs (S-1-5-21-...) with a RID of 1000 or more, and
    # Entra ID user SIDs (S-1-12-1-...). Well-known accounts (RID below 1000, for example
    # Administrator 500, Guest 501, DefaultAccount 503 and WDAGUtilityAccount 504), service
    # and virtual accounts are not allowed. A trailing .bak is ignored.
    #
    # .PARAMETER Sid
    # The SID, or the name of a ProfileList key.
    #
    # .EXAMPLE
    # Test-UserProfileSidAllowed -Sid 'S-1-5-21-1-2-3-1001'
    #
    # # Returns $true. The same SID with RID 500 returns $false.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [bool] $true when the SID is allowed.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [AllowEmptyString()]
        [string]$Sid
    )

    $strBase = $Sid -replace '\.bak$', ''
    if ($strBase -match '^S-1-5-21-(\d+-){3}(?<rid>\d+)$') {
        return ([long]$Matches['rid'] -ge 1000)
    }
    return ($strBase -match '^S-1-12-1-(\d+-)*\d+$')
}


function ConvertTo-UserProfileNormalPath {
    # .SYNOPSIS
    # Returns a full, long-name form of a profile path for comparison.
    #
    # .DESCRIPTION
    # Expands environment variables, removes a \\?\ prefix and a trailing backslash, resolves
    # the path with GetFullPath, and replaces an 8.3 short last segment with the long name when
    # the folder exists. Case is kept. Compare results with OrdinalIgnoreCase. A path that
    # cannot be normalised is returned trimmed, never $null.
    #
    # .PARAMETER Path
    # The path.
    #
    # .EXAMPLE
    # ConvertTo-UserProfileNormalPath -Path 'C:\Users\JOHNDO~1\'
    #
    # # Returns 'C:\Users\John Doe' when that folder exists.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The normalised path.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [AllowEmptyString()]
        [string]$Path
    )

    $strResult = [Environment]::ExpandEnvironmentVariables($Path).Trim()
    if ($strResult.StartsWith('\\?\')) {
        $strResult = $strResult.Substring(4)
    }
    try {
        $strResult = [System.IO.Path]::GetFullPath($strResult).TrimEnd('\')
        $strLeaf = [System.IO.Path]::GetFileName($strResult)
        $strParent = [System.IO.Path]::GetDirectoryName($strResult)
        if (($strLeaf -like '*~*') -and (-not [string]::IsNullOrEmpty($strParent)) -and [System.IO.Directory]::Exists($strResult)) {
            $arrMatch = @([System.IO.Directory]::GetDirectories($strParent, $strLeaf))
            if ($arrMatch.Count -eq 1) {
                $strResult = $arrMatch[0].TrimEnd('\')
            }
        }
    } catch {
        Write-Debug ("Path '{0}' was not normalised: {1}" -f $Path, $_.Exception.Message)
        $strResult = $strResult.TrimEnd('\')
    }
    return $strResult
}


function Get-UserProfileRegisteredPathMap {
    # .SYNOPSIS
    # Maps each path that a ProfileList key points to onto the names of the keys.
    #
    # .DESCRIPTION
    # The map key is the normalised path in lower case. The value is the array of key names
    # (SIDs, including .bak keys) that point to that path.
    #
    # .EXAMPLE
    # $hashtablePath = Get-UserProfileRegisteredPathMap
    #
    # # $hashtablePath['c:\users\bob'] is @('S-1-5-21-1-2-3-1001').
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [hashtable] Normalised lower-case path to string array of key names.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    $hashtableMap = @{}
    foreach ($objKey in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList')) {
        $objImageProperty = (Get-ItemProperty -LiteralPath $objKey.PSPath).PSObject.Properties['ProfileImagePath']
        if (($null -eq $objImageProperty) -or [string]::IsNullOrWhiteSpace([string]$objImageProperty.Value)) {
            continue
        }
        $strNormal = (ConvertTo-UserProfileNormalPath -Path ([string]$objImageProperty.Value)).ToLowerInvariant()
        if (-not $hashtableMap.ContainsKey($strNormal)) {
            $hashtableMap[$strNormal] = @()
        }
        $hashtableMap[$strNormal] = @($hashtableMap[$strNormal]) + [string]$objKey.PSChildName
    }
    return $hashtableMap
}


function Get-UserProfileUnsafeReason {
    # .SYNOPSIS
    # Returns why a profile folder must not be deleted, or $null when it may be.
    #
    # .DESCRIPTION
    # A folder may be deleted only when all of these are true: it is a direct child of the
    # profiles directory; its name is not a known system folder (Default, Public and so on);
    # and no ProfileList key other than the owner's own key (SID and SID.bak) points to it.
    # The last rule keeps a live profile safe when two keys share one folder.
    #
    # .PARAMETER Path
    # Path of the folder.
    #
    # .PARAMETER OwnSid
    # SID of the profile that owns the folder. Empty for an unregistered (orphan) folder.
    #
    # .PARAMETER ProfilesDirectory
    # The profiles directory, for example C:\Users.
    #
    # .PARAMETER PathMap
    # The result of Get-UserProfileRegisteredPathMap.
    #
    # .EXAMPLE
    # Get-UserProfileUnsafeReason -Path 'C:\Users\bob' -OwnSid 'S-1-5-21-1-2-3-1001' -ProfilesDirectory 'C:\Users' -PathMap $hashtablePath
    #
    # # Returns $null when only the owner's keys point to C:\Users\bob.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The reason, or $null.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface. The
    # parameters, the return shape and the positional contract may change without notice.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [AllowEmptyString()]
        [string]$OwnSid,
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,
        [Parameter(Mandatory = $true)]
        [hashtable]$PathMap
    )

    $arrKnownFolder = @('All Users', 'Default', 'Default User', 'Default.migrated', 'LocalService', 'NetworkService', 'Public')
    $strNormalPath = ConvertTo-UserProfileNormalPath -Path $Path
    $strNormalRoot = ConvertTo-UserProfileNormalPath -Path $ProfilesDirectory
    $strParent = [System.IO.Path]::GetDirectoryName($strNormalPath)
    if ([string]::IsNullOrEmpty($strParent) -or (-not $strParent.Equals($strNormalRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        return 'The folder is not directly under the profiles directory.'
    }
    if ($arrKnownFolder -contains [System.IO.Path]::GetFileName($strNormalPath)) {
        return 'The folder is a system profile folder.'
    }
    $strOwnBase = ([string]$OwnSid) -replace '\.bak$', ''
    $strMapKey = $strNormalPath.ToLowerInvariant()
    if ($PathMap.ContainsKey($strMapKey)) {
        foreach ($strKeyName in @($PathMap[$strMapKey])) {
            $strKeyBase = $strKeyName -replace '\.bak$', ''
            if ([string]::IsNullOrEmpty($strOwnBase) -or (-not $strKeyBase.Equals($strOwnBase, [System.StringComparison]::OrdinalIgnoreCase))) {
                return ('Another ProfileList key ({0}) points to the same folder.' -f $strKeyName)
            }
        }
    }
    return $null
}


function Get-UserProfileCleanupItem {
    # .SYNOPSIS
    # Finds user profile data that is stale or orphaned.
    #
    # .DESCRIPTION
    # Streams one object for each item to clean. The Kind property is one of:
    #
    # StaleProfile       A registered profile that is not loaded and has not been used for
    #                    MaxAgeDays days or more. Removing it deletes the folder, the user
    #                    registry hive (NTUSER.DAT) and the ProfileList registration.
    # OrphanRegistration A ProfileList key (including a .bak key) whose profile folder no
    #                    longer exists.
    # OrphanProfileGuid  A ProfileGuid key whose SidString names a ProfileList key that
    #                    no longer exists.
    # OrphanFolder       A profile-shaped folder in the profiles directory that no
    #                    ProfileList key points to, and that is older than MaxAgeDays days.
    #
    # Profile age comes from the profile service timestamps in the registry: the newest of
    # LocalProfileLoadTime, LocalProfileUnLoadTime and LocalProfileCleanupCheckTime. When a
    # profile has none of them (Windows before version 1809), the last write time of
    # NTUSER.MAN or NTUSER.DAT is used. A profile with no usable timestamp is never
    # selected.
    #
    # These items are never selected: loaded profiles (current sign-ins), profiles whose SID
    # is not a local, domain or Entra ID user (SID prefix S-1-5-21- or S-1-12-1-), the
    # built-in Administrator (RID 500), the system profile folders, and any account that
    # matches ExcludeAccount.
    #
    # The function reads only. It makes no change.
    #
    # .PARAMETER MaxAgeDays
    # Days of inactivity at or above which a profile or folder is stale.
    #
    # .PARAMETER ExcludeAccount
    # Wildcard patterns. A match on the SID, the profile folder name, the account name or
    # DOMAIN\name keeps the item. Patterns that contain a backslash cause account name
    # resolution; other patterns do not.
    #
    # .PARAMETER IncludeAccount
    # Wildcard patterns. When set to anything other than '*', only matching items are
    # returned. The default is '*'.
    #
    # .PARAMETER Kind
    # Kinds of item to return. The default is all four.
    #
    # .PARAMETER ReferenceTime
    # The time that ages are measured against, in UTC. The default is the current time.
    #
    # .EXAMPLE
    # Get-UserProfileCleanupItem -MaxAgeDays 90 | Format-Table Kind, Account, AgeDays, Path
    #
    # # Lists every profile item that a 90-day cleanup would remove.
    #
    # .EXAMPLE
    # @(Get-UserProfileCleanupItem -MaxAgeDays 60 -Kind StaleProfile).Count
    #
    # # Returns the number of stale profiles for a 60-day cleanup.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] with the properties Kind, Sid, Account, Path, AgeDays, Basis,
    # LastUsed and Detail. Nothing is returned when no item qualifies.
    #
    # .NOTES
    # This function supports positional parameters:
    #
    #   Position 0: MaxAgeDays
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateRange(1, 3650)]
        [int]$MaxAgeDays,
        [string[]]$ExcludeAccount = @(),
        [string[]]$IncludeAccount = @('*'),
        [ValidateSet('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder')]
        [string[]]$Kind = @('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder'),
        [datetime]$ReferenceTime = [datetime]::UtcNow
    )

    Set-StrictMode -Version Latest
    $strProfileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $strProfileGuidPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid'
    $boolNeedAccountName = $false
    foreach ($strPattern in (@($ExcludeAccount) + @($IncludeAccount))) {
        if ($strPattern -like '*\*') {
            $boolNeedAccountName = $true
        }
    }
    # An unregistered folder has no SID, so it is matched on its name. A DOMAIN\name pattern
    # also matches on the name part, so an exclude pattern keeps a folder of that name.
    $arrFolderExclude = @($ExcludeAccount)
    $arrFolderInclude = @($IncludeAccount)
    foreach ($strPattern in @($ExcludeAccount)) {
        if ($strPattern -like '*\*') {
            $arrFolderExclude += $strPattern.Substring($strPattern.LastIndexOf('\') + 1)
        }
    }
    foreach ($strPattern in @($IncludeAccount)) {
        if ($strPattern -like '*\*') {
            $arrFolderInclude += $strPattern.Substring($strPattern.LastIndexOf('\') + 1)
        }
    }

    $strProfilesDirectory = ConvertTo-UserProfileNormalPath -Path ([string](Get-ItemPropertyValue -LiteralPath $strProfileListPath -Name 'ProfilesDirectory'))
    $arrRegistration = @(Get-ChildItem -LiteralPath $strProfileListPath)

    $hashtableCimBySid = @{}
    foreach ($objCimProfile in @(Get-CimInstance -ClassName Win32_UserProfile)) {
        $hashtableCimBySid[[string]$objCimProfile.SID] = $objCimProfile
    }

    # Every path that a ProfileList key points to. A folder in this map is a registered
    # profile folder, whatever the state of its key.
    $hashtableRegisteredPath = Get-UserProfileRegisteredPathMap

    foreach ($objKey in $arrRegistration) {
        $strKeyName = [string]$objKey.PSChildName
        $strSid = $strKeyName -replace '\.bak$', ''
        $boolIsBackupKey = ($strKeyName -ne $strSid)

        if (-not (Test-UserProfileSidAllowed -Sid $strSid)) {
            continue
        }

        $objProperty = Get-ItemProperty -LiteralPath $objKey.PSPath
        $strImagePath = ''
        if ($null -ne $objProperty.PSObject.Properties['ProfileImagePath']) {
            $strImagePath = [string]$objProperty.PSObject.Properties['ProfileImagePath'].Value
        }
        if ([string]::IsNullOrWhiteSpace($strImagePath)) {
            continue
        }
        $strProfilePath = ConvertTo-UserProfileNormalPath -Path $strImagePath
        $strFolderName = [System.IO.Path]::GetFileName($strProfilePath)

        $boolLoaded = Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $strSid)
        if ($hashtableCimBySid.ContainsKey($strSid) -and $hashtableCimBySid[$strSid].Loaded) {
            $boolLoaded = $true
        }
        if ($boolLoaded) {
            continue
        }

        $strAccount = $strSid
        $arrCandidate = @($strSid, $strFolderName)
        if ($boolNeedAccountName) {
            $strAccount = Resolve-UserProfileAccountName -Sid $strSid
            $arrCandidate += $strAccount
            if ($strAccount.Contains('\')) {
                $arrCandidate += $strAccount.Substring($strAccount.IndexOf('\') + 1)
            }
        }
        if (Test-UserProfileAccountMatch -Pattern $ExcludeAccount -Candidate $arrCandidate) {
            continue
        }
        if (-not (Test-UserProfileAccountMatch -Pattern $IncludeAccount -Candidate $arrCandidate)) {
            continue
        }

        # A folder that does not exist is only an orphan when its parent exists. A missing
        # parent can mean an offline volume.
        $strParent = [System.IO.Path]::GetDirectoryName($strProfilePath)
        if ((-not [string]::IsNullOrEmpty($strParent)) -and
            [System.IO.Directory]::Exists($strParent) -and
            (-not [System.IO.Directory]::Exists($strProfilePath))) {
            if ($Kind -contains 'OrphanRegistration') {
                [pscustomobject]@{
                    Kind = 'OrphanRegistration'
                    Sid = $strKeyName
                    Account = $strAccount
                    Path = $strProfilePath
                    AgeDays = $null
                    Basis = 'None'
                    LastUsed = $null
                    Detail = 'The ProfileList key points to a folder that does not exist.'
                }
            }
            continue
        }

        if ($boolIsBackupKey -or ($Kind -notcontains 'StaleProfile') -or
            (-not [System.IO.Directory]::Exists($strProfilePath))) {
            continue
        }
        # Only a folder that belongs to this SID alone, directly under the profiles directory,
        # may be deleted. A key that shares a folder with another SID, or points at the profiles
        # directory itself, a drive root or a shared folder, is kept.
        $strUnsafe = Get-UserProfileUnsafeReason -Path $strProfilePath -OwnSid $strSid -ProfilesDirectory $strProfilesDirectory -PathMap $hashtableRegisteredPath
        if ($null -ne $strUnsafe) {
            Write-Verbose ("Profile '{0}' is kept: {1}" -f $strProfilePath, $strUnsafe)
            continue
        }

        $objLastUsed = $null
        $strBasis = 'None'
        $arrStamp = @()
        foreach ($strPair in @(
                @('LocalProfileLoadTimeLow', 'LocalProfileLoadTimeHigh'),
                @('LocalProfileUnLoadTimeLow', 'LocalProfileUnLoadTimeHigh'),
                @('LocalProfileCleanupCheckTimeLow', 'LocalProfileCleanupCheckTimeHigh'))) {
            $objLow = $null
            $objHigh = $null
            if ($null -ne $objProperty.PSObject.Properties[$strPair[0]]) {
                $objLow = $objProperty.PSObject.Properties[$strPair[0]].Value
            }
            if ($null -ne $objProperty.PSObject.Properties[$strPair[1]]) {
                $objHigh = $objProperty.PSObject.Properties[$strPair[1]].Value
            }
            $objStamp = ConvertFrom-UserProfileFileTime -LowPart $objLow -HighPart $objHigh
            if ($null -ne $objStamp) {
                $arrStamp += $objStamp
            }
        }
        if ($arrStamp.Count -gt 0) {
            $objLastUsed = ($arrStamp | Measure-Object -Maximum).Maximum
            $strBasis = 'Registry'
        } else {
            foreach ($strHiveName in @('NTUSER.MAN', 'NTUSER.DAT')) {
                $strHivePath = [System.IO.Path]::Combine($strProfilePath, $strHiveName)
                if ([System.IO.File]::Exists($strHivePath)) {
                    $objLastUsed = (Get-Item -LiteralPath $strHivePath -Force).LastWriteTimeUtc
                    $strBasis = $strHiveName
                    break
                }
            }
        }
        if ($null -eq $objLastUsed) {
            Write-Verbose ("Profile '{0}' has no usable timestamp and is kept." -f $strProfilePath)
            continue
        }
        $dblAgeDays = [math]::Floor(($ReferenceTime.ToUniversalTime() - $objLastUsed).TotalDays)
        if ($dblAgeDays -lt 0) {
            $dblAgeDays = 0
        }
        if ($dblAgeDays -ge $MaxAgeDays) {
            [pscustomobject]@{
                Kind = 'StaleProfile'
                Sid = $strSid
                Account = $strAccount
                Path = $strProfilePath
                AgeDays = [int]$dblAgeDays
                Basis = $strBasis
                LastUsed = $objLastUsed
                Detail = 'Not used for {0} days or more.' -f $MaxAgeDays
            }
        }
    }

    if ($Kind -contains 'OrphanProfileGuid') {
        if (Test-Path -LiteralPath $strProfileGuidPath) {
            foreach ($objGuidKey in @(Get-ChildItem -LiteralPath $strProfileGuidPath)) {
                $objGuidProperty = Get-ItemProperty -LiteralPath $objGuidKey.PSPath
                $strSidString = ''
                if ($null -ne $objGuidProperty.PSObject.Properties['SidString']) {
                    $strSidString = [string]$objGuidProperty.SidString
                }
                if ([string]::IsNullOrWhiteSpace($strSidString)) {
                    continue
                }
                if (-not (Test-UserProfileSidAllowed -Sid $strSidString)) {
                    continue
                }
                if (Test-Path -LiteralPath ($strProfileListPath + '\' + $strSidString)) {
                    continue
                }
                if (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $strSidString)) {
                    continue
                }
                if (-not (Test-UserProfileAccountMatch -Pattern $IncludeAccount -Candidate @($strSidString))) {
                    continue
                }
                if (Test-UserProfileAccountMatch -Pattern $ExcludeAccount -Candidate @($strSidString)) {
                    continue
                }
                [pscustomobject]@{
                    Kind = 'OrphanProfileGuid'
                    Sid = $strSidString
                    Account = $strSidString
                    Path = [string]$objGuidKey.PSPath
                    AgeDays = $null
                    Basis = 'None'
                    LastUsed = $null
                    Detail = 'The ProfileGuid key names a SID that has no ProfileList key.'
                }
            }
        }
    }

    if ($Kind -contains 'OrphanFolder') {
        $arrFolder = @(Get-ChildItem -LiteralPath $strProfilesDirectory -Directory -Force)
        foreach ($objFolder in $arrFolder) {
            if (($objFolder.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }
            if ($null -ne (Get-UserProfileUnsafeReason -Path $objFolder.FullName -OwnSid '' -ProfilesDirectory $strProfilesDirectory -PathMap $hashtableRegisteredPath)) {
                continue
            }
            if (Test-UserProfileAccountMatch -Pattern $arrFolderExclude -Candidate @($objFolder.Name)) {
                continue
            }
            if (-not (Test-UserProfileAccountMatch -Pattern $arrFolderInclude -Candidate @($objFolder.Name))) {
                continue
            }
            $strHiveDat = Join-Path -Path $objFolder.FullName -ChildPath 'NTUSER.DAT'
            $strHiveMan = Join-Path -Path $objFolder.FullName -ChildPath 'NTUSER.MAN'
            $strAppData = Join-Path -Path $objFolder.FullName -ChildPath 'AppData'
            $boolHasHive = (Test-Path -LiteralPath $strHiveDat -PathType Leaf) -or (Test-Path -LiteralPath $strHiveMan -PathType Leaf)
            $boolProfileShaped = $boolHasHive -or (Test-Path -LiteralPath $strAppData -PathType Container)
            if (-not $boolProfileShaped) {
                continue
            }
            $objNewest = $objFolder.LastWriteTimeUtc
            foreach ($strHivePath in @($strHiveDat, $strHiveMan)) {
                if (Test-Path -LiteralPath $strHivePath -PathType Leaf) {
                    $objHiveTime = (Get-Item -LiteralPath $strHivePath -Force).LastWriteTimeUtc
                    if ($objHiveTime -gt $objNewest) {
                        $objNewest = $objHiveTime
                    }
                }
            }
            $dblFolderAgeDays = [math]::Floor(($ReferenceTime.ToUniversalTime() - $objNewest).TotalDays)
            if ($dblFolderAgeDays -lt 0) {
                $dblFolderAgeDays = 0
            }
            if ($dblFolderAgeDays -ge $MaxAgeDays) {
                [pscustomobject]@{
                    Kind = 'OrphanFolder'
                    Sid = $null
                    Account = $objFolder.Name
                    Path = $objFolder.FullName
                    AgeDays = [int]$dblFolderAgeDays
                    Basis = 'FolderOrHiveWriteTime'
                    LastUsed = $objNewest
                    Detail = 'No ProfileList key points to this profile-shaped folder.'
                }
            }
        }
    }
}


function Remove-UserProfileCleanupItem {
    # .SYNOPSIS
    # Removes the items that Get-UserProfileCleanupItem returns.
    #
    # .DESCRIPTION
    # Accepts items from the pipeline and removes each one:
    #
    # StaleProfile       Win32_UserProfile instance removed with Remove-CimInstance. The
    #                    profile service deletes the folder, the hive and the ProfileList
    #                    key. The function then checks that the folder is gone.
    # OrphanRegistration Win32_UserProfile instance removed when one exists; otherwise the
    #                    ProfileList key is deleted.
    # OrphanProfileGuid  The ProfileGuid key is deleted.
    # OrphanFolder       The folder is deleted with Remove-UserProfileFolderTree.
    #
    # Before it removes a profile the function checks again that the profile is not loaded.
    # A failure on one item is logged and reported in the output, and the next item is
    # processed. The function supports -WhatIf. The confirm impact is Medium, so no
    # prompt appears unless -Confirm is given.
    #
    # .PARAMETER InputObject
    # An item from Get-UserProfileCleanupItem.
    #
    # .PARAMETER LogPath
    # Full path of a log file. An empty value turns logging off.
    #
    # .EXAMPLE
    # Get-UserProfileCleanupItem -MaxAgeDays 90 | Remove-UserProfileCleanupItem -WhatIf
    #
    # # Shows what a 90-day cleanup would remove. Nothing is deleted.
    #
    # .EXAMPLE
    # Get-UserProfileCleanupItem -MaxAgeDays 90 | Remove-UserProfileCleanupItem -LogPath 'C:\Windows\CCM\Logs\UserProfileCleanup.log'
    #
    # # Removes the items and writes one log line for each.
    #
    # .INPUTS
    # [pscustomobject] An item from Get-UserProfileCleanupItem.
    #
    # .OUTPUTS
    # [pscustomobject] with the properties Kind, Account, Path, Succeeded and Message, one
    # for each item.
    #
    # .NOTES
    # This function does not throw for a failed item. It reports Succeeded = $false.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [pscustomobject]$InputObject,
        [string]$LogPath
    )

    begin {
        Set-StrictMode -Version Latest
        $strProfileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    }

    process {
        $strKind = [string]$InputObject.Kind
        $strTarget = [string]$InputObject.Path
        $boolSucceeded = $false
        $strMessage = ''
        $strAccount = [string]$InputObject.Account
        if (($null -ne $InputObject.Sid) -and ($strAccount -eq [string]$InputObject.Sid)) {
            $strAccount = Resolve-UserProfileAccountName -Sid ([string]$InputObject.Sid -replace '\.bak$', '')
        }

        if (-not $PSCmdlet.ShouldProcess($strTarget, ('Remove {0} ({1})' -f $strKind, $strAccount))) {
            return
        }

        try {
            $strProfilesDirectory = ConvertTo-UserProfileNormalPath -Path ([string](Get-ItemPropertyValue -LiteralPath $strProfileListPath -Name 'ProfilesDirectory'))
            switch ($strKind) {
                'StaleProfile' {
                    $strSid = [string]$InputObject.Sid
                    if (-not (Test-UserProfileSidAllowed -Sid $strSid)) {
                        throw 'The SID is not a user SID that this engine may clean.'
                    }
                    $strUnsafe = Get-UserProfileUnsafeReason -Path $strTarget -OwnSid $strSid -ProfilesDirectory $strProfilesDirectory -PathMap (Get-UserProfileRegisteredPathMap)
                    if ($null -ne $strUnsafe) {
                        throw $strUnsafe
                    }
                    $objCimProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID = '{0}'" -f $strSid)
                    if ($null -eq $objCimProfile) {
                        throw 'The profile service has no Win32_UserProfile instance for this SID.'
                    }
                    if ($objCimProfile.Loaded -or (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $strSid))) {
                        throw 'The profile is loaded now. It is kept.'
                    }
                    Remove-CimInstance -InputObject $objCimProfile -ErrorAction Stop
                    if (Test-Path -LiteralPath $strTarget) {
                        throw 'The profile service removed the registration, but the folder is still there.'
                    }
                    $boolSucceeded = $true
                    $strMessage = 'Profile removed.'
                }
                'OrphanRegistration' {
                    $strKeyName = [string]$InputObject.Sid
                    $strSid = $strKeyName -replace '\.bak$', ''
                    if (-not (Test-UserProfileSidAllowed -Sid $strSid)) {
                        throw 'The SID is not a user SID that this engine may clean.'
                    }
                    if (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $strSid)) {
                        throw 'The user hive is loaded now. It is kept.'
                    }
                    if ($strKeyName -eq $strSid) {
                        $objCimProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID = '{0}'" -f $strSid)
                        if ($null -ne $objCimProfile) {
                            Remove-CimInstance -InputObject $objCimProfile -ErrorAction Stop
                        }
                    }
                    $strKeyPath = $strProfileListPath + '\' + $strKeyName
                    if (Test-Path -LiteralPath $strKeyPath) {
                        Remove-Item -LiteralPath $strKeyPath -Recurse -Force -ErrorAction Stop
                    }
                    $boolSucceeded = $true
                    $strMessage = 'Registration removed.'
                }
                'OrphanProfileGuid' {
                    if (-not (Test-UserProfileSidAllowed -Sid ([string]$InputObject.Sid))) {
                        throw 'The SID is not a user SID that this engine may clean.'
                    }
                    if (-not $strTarget.StartsWith('Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid\', [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw 'The key is not under ProfileGuid.'
                    }
                    if (Test-Path -LiteralPath $strTarget) {
                        Remove-Item -LiteralPath $strTarget -Recurse -Force -ErrorAction Stop
                    }
                    $boolSucceeded = $true
                    $strMessage = 'ProfileGuid key removed.'
                }
                'OrphanFolder' {
                    $strUnsafe = Get-UserProfileUnsafeReason -Path $strTarget -OwnSid '' -ProfilesDirectory $strProfilesDirectory -PathMap (Get-UserProfileRegisteredPathMap)
                    if ($null -ne $strUnsafe) {
                        throw $strUnsafe
                    }
                    Remove-UserProfileFolderTree -Path $strTarget
                    $boolSucceeded = $true
                    $strMessage = 'Folder removed.'
                }
                default {
                    throw ('Unknown item kind: {0}' -f $strKind)
                }
            }
        } catch {
            $strMessage = $_.Exception.Message
            Write-Debug ("Removal of '{0}' failed: {1}" -f $strTarget, $strMessage)
        }

        $strLevel = 'INFO'
        if (-not $boolSucceeded) {
            $strLevel = 'ERROR'
        }
        Write-UserProfileCleanupLog -LogPath $LogPath -Level $strLevel -Message (
            '{0} | {1} | {2} | {3}' -f $strKind, $strAccount, $strTarget, $strMessage)

        [pscustomobject]@{
            Kind = $strKind
            Account = $strAccount
            Path = $strTarget
            Succeeded = $boolSucceeded
            Message = $strMessage
        }
    }
}
