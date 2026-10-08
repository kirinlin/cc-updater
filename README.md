# cc-updater

English | [繁體中文](README-tw.md)

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

The installer saves `DestinationDir` and `TaskName` in `%LOCALAPPDATA%\cc-updater\install-state.json`.

BurntToast installation occurs before the final confirmation. Cancelling can leave the module installed. If module installation fails, the installer warns and continues without update notifications.

"Current user" means the account that runs the elevated process. If you use another administrator account in UAC, the task, BurntToast module, and state file can belong to that account. Use the same account to uninstall.

### Install parameters

| Parameter | Default | Description |
|---|---|---|
| `-SourceScript` | `Update-ClaudeCode.ps1` next to `install.ps1` | Script to patch and install. |
| `-DestinationDir` | prompted (suggested: `C:\scripts`) | Where the patched script is copied. |
| `-LogDir` | prompted (suggested: whatever `$LogDir` is currently set to in the source script) | Log directory baked into the installed script. |
| `-WslUsername` | prompted (suggested: `$env:USERNAME`) | WSL username used to build the `/home/<user>/.local/bin/claude` path. |
| `-TaskName` | `Claude Code Updater` | Scheduled task name. |
| `-Force` | off | Skip only the final confirmation. Missing settings are still prompted for. |

## Usage (manual / one-off run)

```powershell
.\Update-ClaudeCode.ps1
```

The `Update-ClaudeCode.ps1` in this repo ships with placeholder defaults (`C:\logs\cc-updater` for logs, `/home/username/.local/bin/claude` for the WSL binary). Running it as-is checks a WSL user named `username`. Set the log directory with `-LogDir`. To set the WSL path, use `install.ps1` or edit the script directly; there is no WSL path parameter.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-FeedUrl` | `https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/feed.xml` | Changelog feed to read the latest version from. |
| `-LogDir` | `C:\logs\cc-updater` | Directory where daily log files are written. |

## Scheduling

`install.ps1` registers the Scheduled Task for you. For manual registration, first put the configured script at `C:\scripts\Update-ClaudeCode.ps1`. Run these commands in an elevated PowerShell window. Both daily triggers run in the morning, at 09:00 and 11:59:

```powershell
$taskName = 'Claude Code Updater'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\scripts\Update-ClaudeCode.ps1"'
$triggers = @(
    New-ScheduledTaskTrigger -Daily -At '09:00'
    New-ScheduledTaskTrigger -Daily -At '11:59'
)
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME -LogonType S4U -RunLevel Limited

Register-ScheduledTask -TaskName $taskName `
    -Action $action -Trigger $triggers -Principal $principal
```

## Uninstall

Run the uninstaller with the account used for installation:

```powershell
.\uninstall.ps1
```

The script requests elevation if required. It lists the task and script to remove, then asks for confirmation. It removes the scheduled task, installed `Update-ClaudeCode.ps1`, and state file. It keeps log files and BurntToast. If neither the task nor the script exists, it exits and keeps the state file.

| Parameter | Default | Description |
|---|---|---|
| `-DestinationDir` | state file, then `C:\scripts` | Directory that contains the installed script. |
| `-TaskName` | state file, then `Claude Code Updater` | Task to remove. An explicit parameter overrides the state file. |
| `-Force` | off | Skip the final confirmation. Elevation is still required. |

Old state files do not contain `TaskName`. If you used a custom name with an older installer, pass that name with `-TaskName`.

The installer replaces only a task with the same name. It does not migrate or remove an old `cc-updater` task. In an elevated PowerShell window, inspect that task. Remove it only after you confirm it is the old updater task:

```powershell
Get-ScheduledTask -TaskName 'cc-updater' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'cc-updater' -Confirm
```

## Logs

Logs are written per day to `<LogDir>\cc-updater_YYYY-MM-DD.log`, e.g.:

```
C:\logs\cc-updater\cc-updater_2026-07-08.log
```

Each line is timestamped and tagged with a level (`INFO`, `WARN`, `ERROR`).

## Disable Automatic Background Updates

Set `DISABLE_AUTOUPDATER` to `1` to disable automatic background updates. Manual claude update still works.

Add this to your `~/.claude/settings.json` file:

```json
   {
     "env": {
       "DISABLE_AUTOUPDATER": 1
     }
   }
```
