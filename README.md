# cc-updater

**Claude Code native installations automatically update in the background.**

PowerShell scripts that keep the Claude Code CLI up to date on both Windows and WSL.

## What it does

1. Fetches the [Claude Code changelog feed](https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/feed.xml) and reads the latest release tag.
2. Checks the installed Windows `claude` version (`claude --version`).
3. Checks the installed WSL `claude` version (`wsl bash -l -c ".../claude --version"`).
4. For each installation that is older than the latest release, runs the corresponding upgrade command:
   - Windows: `claude upgrade`
   - WSL: `wsl bash -l -c ".../claude update"`
5. Logs every step to a daily log file and to the console.
6. Shows a Windows toast notification (via [BurntToast](https://github.com/Windos/BurntToast)) after each successful upgrade, e.g. "Windows claude code updated from version 1.2.3 to 1.2.4".

The Windows and WSL checks run independently — if one fails (e.g. WSL isn't installed), it's logged as an error but the other check still runs.

## Install

`install.ps1` sets up `Update-ClaudeCode.ps1` to run automatically on this machine:

```powershell
.\install.ps1
```

It will:

- Relaunch itself in an elevated PowerShell window if it isn't already running as Administrator (registering a scheduled task requires it).
- Install the [BurntToast](https://github.com/Windos/BurntToast) module for the current user if it isn't already installed (needed for update toast notifications).
- Prompt for the log directory, WSL username, and script install directory (or take them as parameters).
- Patch a copy of `Update-ClaudeCode.ps1` with those values — setting the `-LogDir` default and rewriting the WSL `claude` path to `/home/<WslUsername>/.local/bin/claude`.
- Copy the patched script to the install directory.
- Register (or replace) a Scheduled Task that runs the script twice daily, at 9:00 AM and 11:59 AM, as the current user.

### Install parameters

| Parameter | Default | Description |
|---|---|---|
| `-SourceScript` | `Update-ClaudeCode.ps1` next to `install.ps1` | Script to patch and install. |
| `-DestinationDir` | prompted (suggested: `C:\scripts`) | Where the patched script is copied. |
| `-LogDir` | prompted (suggested: whatever `$LogDir` is currently set to in the source script) | Log directory baked into the installed script. |
| `-WslUsername` | prompted (suggested: `$env:USERNAME`) | WSL username used to build the `/home/<user>/.local/bin/claude` path. |
| `-TaskName` | `Claude Code Updater` | Scheduled task name. |
| `-Force` | off | Skip the confirmation prompt before installing. |

## Usage (manual / one-off run)

```powershell
.\Update-ClaudeCode.ps1
```

The `Update-ClaudeCode.ps1` in this repo ships with placeholder defaults (`C:\logs\cc-updater` for logs, `/home/username/.local/bin/claude` for the WSL binary) — running it as-is checks a WSL user literally named `username`. Use `install.ps1` to patch in your real values, or edit the script directly, or pass parameters:

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-FeedUrl` | `https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/feed.xml` | Changelog feed to read the latest version from. |
| `-LogDir` | `C:\logs\cc-updater` | Directory where daily log files are written. |

## Scheduling

`install.ps1` (see above) registers the Scheduled Task for you. To do it by hand instead:

```powershell
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\scripts\Update-ClaudeCode.ps1"'
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
Register-ScheduledTask -TaskName 'cc-updater' -Action $action -Trigger $trigger
```

## Logs

Logs are written per day to `<LogDir>\cc-updater_YYYY-MM-DD.log`, e.g.:

```
C:\logs\cc-updater\cc-updater_2026-07-08.log
```

Each line is timestamped and tagged with a level (`INFO`, `WARN`, `ERROR`).
