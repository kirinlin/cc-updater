<#
.SYNOPSIS
    Uninstaller for the Claude Code updater script.

.DESCRIPTION
    Removes the scheduled task registered by install.ps1 and deletes the
    copied Update-ClaudeCode.ps1 from the destination directory. If
    -DestinationDir isn't passed, it's read from the state file install.ps1
    wrote on install.
#>

[CmdletBinding()]
param(
    [string]$DestinationDir,
    [string]$TaskName = 'Claude Code Updater',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Same fixed location install.ps1 writes to.
$stateFile = Join-Path $env:LOCALAPPDATA 'cc-updater\install-state.json'

# --- Unregistering the scheduled task requires administrator privileges.
#     Relaunch elevated if we're not already running as one. ---
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isElevated = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isElevated) {
    Write-Warning "This uninstaller removes a scheduled task, which requires administrator privileges."
    Write-Warning "Relaunching in an elevated PowerShell window..."

    $relaunchArgs = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch]) {
            if ($value.IsPresent) { $relaunchArgs += "-$key" }
        }
        else {
            $relaunchArgs += "-$key"
            $relaunchArgs += "`"$value`""
        }
    }

    Start-Process -FilePath 'powershell.exe' -ArgumentList ($relaunchArgs -join ' ') -Verb RunAs
    return
}

if (-not $DestinationDir) {
    if (Test-Path -LiteralPath $stateFile) {
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $DestinationDir = $state.DestinationDir
    }
    if (-not $DestinationDir) {
        $DestinationDir = 'C:\scripts'
    }
}

$destinationScript = Join-Path $DestinationDir 'Update-ClaudeCode.ps1'
$taskExists = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
$fileExists = Test-Path -LiteralPath $destinationScript

if (-not $taskExists -and -not $fileExists) {
    Write-Host "Nothing to uninstall: no '$TaskName' task and no file at $destinationScript."
    return
}

Write-Host ""
Write-Host "About to:"
if ($taskExists) { Write-Host "  - Unregister scheduled task '$TaskName'" }
if ($fileExists) { Write-Host "  - Delete $destinationScript" }
Write-Host ""
if (-not $Force) {
    $confirm = Read-Host "Proceed? (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Aborted."
        return
    }
}

if ($taskExists) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Unregistered scheduled task '$TaskName'."
}

if ($fileExists) {
    Remove-Item -LiteralPath $destinationScript -Force
    Write-Host "Deleted $destinationScript."
}

if (Test-Path -LiteralPath $stateFile) {
    Remove-Item -LiteralPath $stateFile -Force
}

Write-Host "Done."
