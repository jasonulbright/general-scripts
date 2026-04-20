<#
.SYNOPSIS
    Checks PowerShell scripts for syntax (parse) errors using the AST.

.DESCRIPTION
    Parses all .ps1 and .psm1 files under a directory (or a single file)
    and reports any syntax errors. Returns exit code 1 if errors are found.

.PARAMETER Path
    Path to a file or directory. If a directory, all .ps1 and .psm1 files
    are scanned recursively.

.EXAMPLE
    .\Test-ScriptSyntax.ps1 -Path C:\projects\mymodule
    Checks all PS1/PSM1 files for parse errors.
#>
param(
    [Parameter(Mandatory)]
    [string]$Path
)

if (Test-Path $Path -PathType Container) {
    $scripts = Get-ChildItem -Path $Path -Include '*.ps1','*.psm1' -Recurse -File
} elseif (Test-Path $Path -PathType Leaf) {
    $scripts = @(Get-Item $Path)
} else {
    Write-Error "Path not found: $Path"
    exit 1
}

$errors = @()
foreach ($s in $scripts) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($e in $parseErrors) {
        $errors += "$($s.Name):$($e.Extent.StartLineNumber): $($e.Message)"
    }
}

Write-Host "Checked $($scripts.Count) script(s)."
if ($errors.Count -gt 0) {
    Write-Host "ERRORS:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "OK - no parse errors." -ForegroundColor Green
}
