<#
.SYNOPSIS
    Interactive installer for the Claude Code updater script.

.DESCRIPTION
    Prompts for the log directory and WSL username, patches Update-ClaudeCode.ps1
    accordingly, copies it into a script directory, and registers a scheduled
    task (running as the current user) that executes it twice daily, at
    9:00 AM and 11:59 AM.
#>

[CmdletBinding()]
param(
    [string]$SourceScript,
    [string]$DestinationDir,
    [string]$LogDir,
    [string]$WslUsername,
    [string]$TaskName = 'Claude Code Updater',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty when read from a param() default value in this
# host/invocation combo, so resolve the SourceScript default here instead.
if (-not $SourceScript) {
    $SourceScript = Join-Path $PSScriptRoot 'Update-ClaudeCode.ps1'
}

# --- Registering/updating the scheduled task requires administrator
#     privileges. Relaunch elevated if we're not already running as one. ---
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isElevated = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isElevated) {
    Write-Warning "This installer registers a scheduled task, which requires administrator privileges."
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

if (-not (Test-Path -LiteralPath $SourceScript)) {
    throw "Source script not found: $SourceScript"
}

$sourceContent = Get-Content -LiteralPath $SourceScript -Raw

# --- Derive defaults from the existing script content ---
$defaultLogDir = 'C:\logs\cc-updater'
$logDirMatch = [regex]::Match($sourceContent, "LogDir\s*=\s*'([^']*)'")
if ($logDirMatch.Success) { $defaultLogDir = $logDirMatch.Groups[1].Value }

$defaultWslUsername = $env:USERNAME
$defaultDestinationDir = 'C:\scripts'

# --- Prompt for values not supplied on the command line ---
if (-not $LogDir) {
    $response = Read-Host "Log directory [$defaultLogDir]"
    $LogDir = if ([string]::IsNullOrWhiteSpace($response)) { $defaultLogDir } else { $response }
}

if (-not $WslUsername) {
    $response = Read-Host "WSL username [$defaultWslUsername]"
    $WslUsername = if ([string]::IsNullOrWhiteSpace($response)) { $defaultWslUsername } else { $response }
}

if (-not $DestinationDir) {
    $response = Read-Host "Script install directory [$defaultDestinationDir]"
    $DestinationDir = if ([string]::IsNullOrWhiteSpace($response)) { $defaultDestinationDir } else { $response }
}

Write-Host ""
Write-Host "About to:"
Write-Host "  - Set LogDir to:        $LogDir"
Write-Host "  - Set WSL username to:  $WslUsername"
Write-Host "  - Copy script to:       $DestinationDir\Update-ClaudeCode.ps1"
Write-Host "  - Register scheduled task '$TaskName' (daily at 9:00 AM and 11:59 AM) running as $env:USERNAME"
Write-Host ""
if (-not $Force) {
    $confirm = Read-Host "Proceed? (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Aborted."
        return
    }
}

# --- Patch the script content (use MatchEvaluators so $ and \ in the
#     replacement values are never reinterpreted as regex backreferences) ---
$logDirEvaluator = {
    param($m)
    $m.Groups[1].Value + "'" + $LogDir + "'"
}.GetNewClosure()
$patchedContent = [regex]::Replace(
    $sourceContent,
    "(\[string\]\`$LogDir\s*=\s*)'[^']*'",
    $logDirEvaluator
)

$wslUserEvaluator = {
    param($m)
    "/home/$WslUsername/.local/bin/claude"
}.GetNewClosure()
$patchedContent = [regex]::Replace(
    $patchedContent,
    '/home/[^/]+/\.local/bin/claude',
    $wslUserEvaluator
)

# --- Copy the patched script into place ---
if (-not (Test-Path -LiteralPath $DestinationDir)) {
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
}
$destinationScript = Join-Path $DestinationDir 'Update-ClaudeCode.ps1'
Set-Content -LiteralPath $destinationScript -Value $patchedContent -Encoding UTF8
Write-Host "Installed script to $destinationScript"

# --- Register the scheduled task ---
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$destinationScript`""
$trigger = @(
    New-ScheduledTaskTrigger -Daily -At 9:00AM
    New-ScheduledTaskTrigger -Daily -At 11:59AM
)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Task '$TaskName' already exists, replacing it."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
    -Description 'Checks and upgrades the Claude Code CLI (Windows + WSL) twice daily.' | Out-Null

Write-Host "Registered scheduled task '$TaskName' to run daily at 9:00 AM and 11:59 AM as $env:USERNAME."
Write-Host "Done."
