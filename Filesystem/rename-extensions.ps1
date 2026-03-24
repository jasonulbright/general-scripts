<#
.SYNOPSIS
    Obfuscates or restores file extensions to bypass email attachment filters.

.DESCRIPTION
    Renames all file extensions in a directory (recursively) by prepending "not"
    to the extension:  .ps1 -> .notps1,  .exe -> .notexe,  .bat -> .notbat

    Use -Undo to reverse:  .notps1 -> .ps1,  .notexe -> .exe
    Use -Archive to also create a .zip of the folder after renaming.

.EXAMPLE
    .\rename-extensions.ps1 -Path C:\temp\packagers
    .\rename-extensions.ps1 -Path C:\temp\packagers -Archive
    .\rename-extensions.ps1 -Path C:\temp\packagers -Undo
#>
param(
    [Parameter(Mandatory)]
    [string]$Path,
    [switch]$Undo,
    [switch]$Archive
)

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Directory not found: $Path"
    exit 1
}

$files = Get-ChildItem -Path $Path -File -Recurse

$count = 0
foreach ($f in $files) {
    $ext = $f.Extension  # includes the dot, e.g. ".ps1"
    if (-not $ext) { continue }

    if ($Undo) {
        # .notps1 -> .ps1
        if ($ext -match '^\.not(.+)$') {
            $newName = $f.BaseName + '.' + $Matches[1]
            Rename-Item -LiteralPath $f.FullName -NewName $newName
            Write-Host "  $($f.Name) -> $newName"
            $count++
        }
    }
    else {
        # .ps1 -> .notps1  (skip if already obfuscated)
        if ($ext -match '^\.not') { continue }
        $newName = $f.BaseName + '.not' + $ext.TrimStart('.')
        Rename-Item -LiteralPath $f.FullName -NewName $newName
        Write-Host "  $($f.Name) -> $newName"
        $count++
    }
}

Write-Host "`n$count file(s) renamed."

if ($Archive -and -not $Undo) {
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
    $folderName = Split-Path -Leaf $resolvedPath
    $zipPath = Join-Path (Split-Path -Parent $resolvedPath) "$folderName.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path "$resolvedPath\*" -DestinationPath $zipPath -Force
    Write-Host "Archive created: $zipPath"
}
