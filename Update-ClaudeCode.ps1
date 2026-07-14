<#
.SYNOPSIS
    Checks the installed Claude Code CLI version (Windows and WSL) against the latest
    published release and upgrades whichever installation is out of date.
#>

[CmdletBinding()]
param(
    [string]$FeedUrl = 'https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/feed.xml',
    [string]$LogDir  = 'C:\logs\cc-updater'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$logFile = Join-Path $LogDir "cc-updater_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $logFile -Value $line
    Write-Host $line
}

function Show-UpdateToast {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$OldVersion,
        [Parameter(Mandatory)][string]$NewVersion
    )
    try {
        Import-Module BurntToast -ErrorAction Stop
        New-BurntToastNotification -Text "$Label Claude Code Updated", "From $OldVersion to $NewVersion"
    }
    catch {
        Write-Log "Failed to show update toast notification: $($_.Exception.Message)" -Level WARN
    }
}

function Update-ClaudeInstallation {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$GetVersionCommand,
        [Parameter(Mandatory)][scriptblock]$UpgradeCommand,
        [Parameter(Mandatory)][version]$LatestVersion
    )

    try {
        Write-Log "Checking $Label claude CLI version"
        $rawVersion = (& $GetVersionCommand 2>&1) -join ' '
        Write-Log "$Label raw version output: $rawVersion"

        $match = [regex]::Match($rawVersion, '\d+\.\d+\.\d+')
        if (-not $match.Success) {
            throw "Could not parse $Label claude version from output: $rawVersion"
        }
        $localVersionString = $match.Value
        $localVersion = [version]$localVersionString
        Write-Log "$Label installed version: $localVersionString"

        if ($localVersion -lt $LatestVersion) {
            Write-Log "$Label installed version ($localVersionString) is older than latest ($LatestVersion). Running upgrade."
            $upgradeOutput = (& $UpgradeCommand 2>&1) -join "`n"
            Write-Log "$Label upgrade output: $upgradeOutput"
            Write-Log "$Label upgrade command completed."

            $rawVersionAfter = (& $GetVersionCommand 2>&1) -join ' '
            $matchAfter = [regex]::Match($rawVersionAfter, '\d+\.\d+\.\d+')
            if ($matchAfter.Success) {
                $newVersionString = $matchAfter.Value
                Write-Log "$Label version after upgrade: $newVersionString"
                Show-UpdateToast -Label $Label -OldVersion $localVersionString -NewVersion $newVersionString
            }
            else {
                Write-Log "Could not parse $Label claude version after upgrade from output: $rawVersionAfter" -Level WARN
            }
        }
        else {
            Write-Log "$Label installed version ($localVersionString) is up to date (latest: $LatestVersion). No action taken."
        }
    }
    catch {
        Write-Log "$Label check failed: $($_.Exception.Message)" -Level ERROR
    }
}

try {
    Write-Log "===== cc-updater run started ====="

    # ===== BEGIN deployment check (stripped by install.ps1 from the deployed copy) =====
    $scriptSource = Get-Content -LiteralPath $PSCommandPath -Raw
    if ($scriptSource -match '/home/username/\.local/bin/claude') {
        Write-Log "This script still contains the placeholder WSL path (/home/username/...). It looks like it is running from the repo checkout rather than a copy deployed via install.ps1." -Level WARN
    }
    # ===== END deployment check =====

    Write-Log "Fetching release feed from $FeedUrl"
    $feedContent = (Invoke-WebRequest -Uri $FeedUrl -UseBasicParsing).Content
    [xml]$feedXml = $feedContent

    $latestEntry = $feedXml.feed.entry | Select-Object -First 1
    if (-not $latestEntry) {
        throw "No entries found in release feed."
    }

    $latestTag = ($latestEntry.id -split '/tag/')[-1]
    $latestVersionString = $latestTag.TrimStart('v')
    $latestVersion = [version]$latestVersionString
    Write-Log "Latest available version: $latestVersionString"

    Update-ClaudeInstallation -Label 'Windows' -LatestVersion $latestVersion `
        -GetVersionCommand { claude --version } `
        -UpgradeCommand { claude upgrade }

    Update-ClaudeInstallation -Label 'WSL' -LatestVersion $latestVersion `
        -GetVersionCommand { wsl bash -l -c "/home/username/.local/bin/claude --version" } `
        -UpgradeCommand { wsl bash -l -c "/home/username/.local/bin/claude update" }

    Write-Log "===== cc-updater run finished ====="
    Write-Host "`nUpdate complete. You can close/exit this window now."
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" -Level ERROR
    Write-Log "===== cc-updater run finished with errors ====="
    Write-Host "`nUpdate finished with errors. You can close/exit this window now."
    exit 1
}
