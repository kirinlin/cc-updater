# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Two PowerShell scripts, no build/package/test tooling — meant to be run directly:

- [Update-ClaudeCode.ps1](Update-ClaudeCode.ps1) — checks whether the Claude Code CLI is up to date on both Windows and WSL, and upgrades whichever is behind. Meant to be run directly or via Scheduled Task.
- [install.ps1](install.ps1) — interactive installer. Patches a copy of `Update-ClaudeCode.ps1` with a real log directory and WSL username, copies it to a destination folder, and registers a Scheduled Task that runs it twice daily.

The `Update-ClaudeCode.ps1` checked into this repo ships with placeholder defaults (`C:\logs\cc-updater`, WSL user `username`) rather than machine-specific values — `install.ps1` is what bakes in the real values for a given machine.

Both scripts depend on the [BurntToast](https://github.com/Windos/BurntToast) module for Windows toast notifications; `install.ps1` installs it (`-Scope CurrentUser`) if missing, and `Update-ClaudeCode.ps1` shows a toast after each successful upgrade.

## Running / testing changes

```powershell
.\Update-ClaudeCode.ps1
```

There are no automated tests. To validate a change, run the script and inspect both the console output and the day's log file under `<LogDir>\cc-updater_YYYY-MM-DD.log`. Since the log file is dated, re-running on the same day appends to the same file — check for duplicate/interleaved run blocks (`===== cc-updater run started =====` / `... finished =====`) when testing repeatedly.

`install.ps1` is riskier to test: it self-elevates (relaunches itself with `-Verb RunAs` if not already Administrator) and registers/replaces a real Scheduled Task. When testing changes to it, pass a throwaway `-TaskName` and clean up afterward with `Unregister-ScheduledTask -TaskName <name>`.

## Architecture

### Update-ClaudeCode.ps1

Three phases, all in one file:

1. **Fetch latest version** — downloads the Claude Code changelog Atom feed (`feed.xml` from the `anthropics/claude-code` repo), parses it as XML, and takes the first `<entry>` (feed is newest-first). The version tag is extracted from the entry's `<id>` (`.../releases/tag/vX.Y.Z`), not from `<title>`.
2. **Check + upgrade, per installation** — `Update-ClaudeInstallation` is a generic helper that takes a `-GetVersionCommand` and `-UpgradeCommand` scriptblock plus a `-Label`. It's called once for Windows (`claude --version` / `claude upgrade`) and once for WSL (`wsl bash -l -c "/home/username/.local/bin/claude --version"` / `... claude update`). Note the asymmetry: Windows uses `claude upgrade`, WSL uses `claude update` — this is intentional, not a typo. The `/home/username/...` path is a placeholder meant to be rewritten by `install.ps1` (or manually) to the real WSL username. After a successful upgrade, it re-runs `-GetVersionCommand` to get the new version and calls `Show-UpdateToast` with the old/new version strings.
3. **Logging** — `Write-Log` writes timestamped, leveled (`INFO`/`WARN`/`ERROR`) lines to both the console and a daily log file in `-LogDir`.
4. **Toast notification** — `Show-UpdateToast` imports `BurntToast` and calls `New-BurntToastNotification` with a message like `"Windows claude code updated from version 1.2.3 to 1.2.4"`. Import/notify failures (e.g. module not installed) are caught and logged as `WARN`, not fatal — a missing BurntToast module never blocks or fails the update itself.

Each installation check runs in its own try/catch inside `Update-ClaudeInstallation`, so a failure on one (e.g. WSL not installed) is logged as an `ERROR` but doesn't stop the other installation from being checked. The outer script-level try/catch only guards feed-fetching/parsing, which both checks depend on.

Versions are compared using PowerShell's `[version]` type (parsed from the `X.Y.Z` pattern via regex), not string comparison.

### install.ps1

1. **Self-elevation** — checks `WindowsPrincipal.IsInRole(Administrator)`; if not elevated, relaunches itself via `Start-Process -Verb RunAs`, forwarding all bound parameters (switches and values are reconstructed separately since `-Force` needs no value), then returns.
2. **BurntToast check** — after validating `$SourceScript` exists, checks `Get-Module -ListAvailable -Name BurntToast` and, if missing, installs it with `Install-Module -Scope CurrentUser -Force -SkipPublisherCheck`. A failed install only warns; it doesn't abort the rest of the installer.
3. **Defaults from existing content** — reads `$SourceScript` and regex-extracts the current `$LogDir` default to use as the suggested value in the prompt; `$env:USERNAME` is the suggested WSL username.
4. **Prompts** — for any of `LogDir` / `WslUsername` / `DestinationDir` not passed as parameters, via `Read-Host`. `-Force` only skips the final yes/no confirmation, not these prompts.
5. **Patching** — uses `[regex]::Replace` with `MatchEvaluator` scriptblocks (not plain string substitution) to rewrite the `$LogDir` default and the `/home/<user>/.local/bin/claude` path in the script content. This is deliberate: a plain string replacement would treat `$` and `\` in the substituted values as regex backreference syntax.
6. **Install + schedule** — copies the patched content to `$DestinationDir\Update-ClaudeCode.ps1`, then registers a Scheduled Task (`S4U` logon type, `Limited` run level, running as the current user) with two daily triggers at 9:00 AM and 11:59 AM. An existing task with the same `-TaskName` is unregistered first and replaced.
