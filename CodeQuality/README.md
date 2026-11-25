# CodeQuality

Small developer tools that check and repair PowerShell and WPF source code. They do not need ConfigMgr.

The two `.ps1` tools only read files. The two `Fix-*.py` tools edit the files that you pass them, in place, with no backup. Commit or back up the files first.

## Contents

| File | Language | Purpose |
|------|----------|---------|
| `Find-EmptyCatchBlocks.ps1` | PowerShell | Finds empty `catch {}` blocks in `.ps1` and `.psm1` files with AST analysis. Use it to audit the error handling of a module or script tree. |
| `Fix-PsClosures.py` | Python 3 | Adds `.GetNewClosure()` to script blocks that are passed to `.Add_Xxx(...)` event-handler methods, where a captured variable would otherwise go stale. Safe to run again (idempotent). |
| `Fix-WpfButtonCasing.py` | Python 3 | Adds `Controls:ControlsHelper.ContentCharacterCasing="Normal"` to each `<Button>` in a WPF XAML file that does not set it. Safe to run again (idempotent). |
| `Test-ScriptSyntax.ps1` | PowerShell | Checks scripts for syntax (parse) errors with the AST. The exit code is 1 when any script fails to parse, so it works as a pre-commit or CI gate. |

## Requirements

- PowerShell 5.1 or later for the `.ps1` files.
- Python 3 for the `.py` files.
