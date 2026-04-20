<#
.SYNOPSIS
    Finds empty catch blocks in PowerShell scripts using AST analysis.

.DESCRIPTION
    Parses one or more .ps1/.psm1 files using the PowerShell AST and reports
    any catch blocks with zero statements. Useful for auditing error handling
    quality across a codebase.

.PARAMETER Path
    Path to a file or directory. If a directory, all .ps1 and .psm1 files
    are scanned recursively.

.EXAMPLE
    .\Find-EmptyCatchBlocks.ps1 -Path C:\projects\mymodule
    Scans all PS1/PSM1 files under the directory.

.EXAMPLE
    .\Find-EmptyCatchBlocks.ps1 -Path .\MyScript.ps1
    Scans a single file.
#>
param(
    [Parameter(Mandatory)]
    [string]$Path
)

if (Test-Path $Path -PathType Container) {
    $files = Get-ChildItem -Path $Path -Include '*.ps1','*.psm1' -Recurse -File
} elseif (Test-Path $Path -PathType Leaf) {
    $files = @(Get-Item $Path)
} else {
    Write-Error "Path not found: $Path"
    exit 1
}

$totalEmpty = 0
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    $AST = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    $catches = $AST.FindAll({ $args[0] -is [System.Management.Automation.Language.CatchClauseAst] }, $true)
    $empty = $catches | Where-Object { $_.Body.Statements.Count -eq 0 }
    foreach ($c in $empty) {
        $preview = $c.Extent.Text.Substring(0, [Math]::Min(80, $c.Extent.Text.Length))
        Write-Host "$($file.Name):$($c.Extent.StartLineNumber): $preview" -ForegroundColor Yellow
        $totalEmpty++
    }
}

Write-Host "`nScanned $($files.Count) file(s), found $totalEmpty empty catch block(s)." -ForegroundColor $(if ($totalEmpty -gt 0) { 'Red' } else { 'Green' })
