# cc-updater

[English](README.md) ｜ 繁體中文

**Claude Code 原生安裝會在背景自動更新。**

一組 PowerShell 指令碼，讓 Windows 與 WSL 上的 Claude Code CLI 保持最新版本。

## 運作方式

1. 抓取 [Claude Code 變更記錄 feed](https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/feed.xml)，讀取最新的發行版本標籤。
2. 檢查 Windows 上已安裝的 `claude` 版本（`claude --version`）。
3. 檢查 WSL 上已安裝的 `claude` 版本（`wsl bash -l -c ".../claude --version"`）。
4. 對每個版本低於最新發行版本的安裝，執行對應的升級指令：
   - Windows：`claude upgrade`
   - WSL：`wsl bash -l -c ".../claude update"`
5. 將每個步驟寫入每日日誌檔案與主控台。
6. 每次升級成功後，透過 [BurntToast](https://github.com/Windos/BurntToast) 顯示 Windows 快顯通知，例如 `Windows claude code updated from version 1.2.3 to 1.2.4`。

Windows 與 WSL 的檢查各自獨立執行。如果其中一項失敗（例如未安裝 WSL），系統會記錄為錯誤，另一項檢查仍會執行。

## 安裝

`install.ps1` 會設定 `Update-ClaudeCode.ps1`，讓它在這台機器上自動執行：

```powershell
.\install.ps1
```

它會：

- 在尚未以系統管理員身分執行時，於提升權限的 PowerShell 視窗中重新啟動自己（註冊排程工作需要系統管理員權限）。
- 在尚未安裝 [BurntToast](https://github.com/Windos/BurntToast) 模組時，為目前使用者安裝該模組（顯示更新快顯通知需要此模組）。
- 提示輸入日誌目錄、WSL 使用者名稱與指令碼安裝目錄（也可用參數傳入）。
- 用這些值修補 `Update-ClaudeCode.ps1` 的複本：設定 `-LogDir` 預設值，並將 WSL 的 `claude` 路徑改寫為 `/home/<WslUsername>/.local/bin/claude`。
- 將修補後的指令碼複製到安裝目錄。
- 註冊（或取代）排程工作，以目前使用者身分每天在 09:00 與 11:59 執行指令碼。

安裝程式會將 `DestinationDir` 與 `TaskName` 儲存至 `%LOCALAPPDATA%\cc-updater\install-state.json`。

安裝程式會在最終確認之前嘗試安裝 BurntToast。即使取消安裝，模組也可能已安裝。模組安裝失敗時，安裝程式會警告並繼續，但無法顯示更新通知。

「目前使用者」是執行提升權限程序的帳號。若在 UAC 使用另一個管理員帳號，排程工作、BurntToast 模組與狀態檔可能屬於該帳號。解除安裝時請使用相同帳號。

### 安裝參數

| 參數 | 預設值 | 說明 |
|---|---|---|
| `-SourceScript` | 與 `install.ps1` 同目錄的 `Update-ClaudeCode.ps1` | 要修補並安裝的指令碼。 |
| `-DestinationDir` | 提示輸入（建議值 `C:\scripts`） | 修補後指令碼的複製目的地。 |
| `-LogDir` | 提示輸入（建議值為來源指令碼中目前的 `$LogDir` 設定） | 寫入已安裝指令碼的日誌目錄。 |
| `-WslUsername` | 提示輸入（建議值 `$env:USERNAME`） | 用來組成 `/home/<user>/.local/bin/claude` 路徑的 WSL 使用者名稱。 |
| `-TaskName` | `Claude Code Updater` | 排程工作名稱。 |
| `-Force` | 關閉 | 只略過最終確認。未提供的設定值仍會提示輸入。 |

## 手動執行

```powershell
.\Update-ClaudeCode.ps1
```

這個儲存庫中的 `Update-ClaudeCode.ps1` 附帶佔位用的預設值（日誌目錄為 `C:\logs\cc-updater`，WSL 執行檔為 `/home/username/.local/bin/claude`）。直接執行會檢查名稱是 `username` 的 WSL 使用者。日誌目錄可透過 `-LogDir` 設定。WSL 路徑須由 `install.ps1` 修補或直接編輯；指令碼沒有 WSL 路徑參數。

### 參數

| 參數 | 預設值 | 說明 |
|---|---|---|
| `-FeedUrl` | `https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/feed.xml` | 讀取最新版本的變更記錄 feed。 |
| `-LogDir` | `C:\logs\cc-updater` | 寫入每日日誌檔案的目錄。 |

## 排程

`install.ps1` 會為你註冊排程工作。手動註冊前，請先將已完成設定的指令碼放在 `C:\scripts\Update-ClaudeCode.ps1`。接著在提升權限的 PowerShell 視窗執行下列指令。兩個每日觸發器分別在 09:00 與 11:59 執行，兩者皆為上午：

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

## 解除安裝

請使用安裝時的帳號執行：

```powershell
.\uninstall.ps1
```

指令碼會在需要時要求提升權限，列出要移除的排程工作與指令碼，然後要求確認。它會移除排程工作、已安裝的 `Update-ClaudeCode.ps1` 與狀態檔，並保留日誌檔案及 BurntToast。若排程工作與指令碼都不存在，它會直接結束並保留狀態檔。

| 參數 | 預設值 | 說明 |
|---|---|---|
| `-DestinationDir` | 狀態檔中的目錄，其次為 `C:\scripts` | 已安裝指令碼所在的目錄。 |
| `-TaskName` | 狀態檔中的名稱，其次為 `Claude Code Updater` | 要移除的工作。明確傳入的參數優先於狀態檔。 |
| `-Force` | 關閉 | 略過最終確認，仍需提升權限。 |

舊狀態檔沒有 `TaskName`。若使用舊版安裝程式安裝自訂名稱的工作，請以 `-TaskName` 傳入該名稱。

安裝程式只取代同名工作，不會遷移或移除舊的 `cc-updater` 工作。請在提升權限的 PowerShell 視窗檢查該工作。確認它是舊版更新工作後，再移除：

```powershell
Get-ScheduledTask -TaskName 'cc-updater' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'cc-updater' -Confirm
```

## 日誌

日誌會以每天一個檔案的方式寫入 `<LogDir>\cc-updater_YYYY-MM-DD.log`，例如：

```text
C:\logs\cc-updater\cc-updater_2026-07-08.log
```

每一行都有時間戳記，並標上層級（`INFO`、`WARN`、`ERROR`）。

## 停用自動背景更新

將 `DISABLE_AUTOUPDATER` 設為 `1`，即可停用自動背景更新；手動執行 `claude update` 仍可正常運作。

請將以下內容加入 `~/.claude/settings.json` 檔案：

```json
   {
     "env": {
       "DISABLE_AUTOUPDATER": 1
     }
   }
```
