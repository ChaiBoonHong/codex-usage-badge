# Windows guide

## Install in one step

1. Download and fully extract the Windows ZIP.
2. Open the extracted folder and double-click **`START-HERE.cmd`**.
3. Open and sign in to Codex once if you have not already.
4. When installation finishes, fully quit Codex, including its tray process, then reopen it from the normal Codex icon.

The installer uses the current user account only. It installs to `%LOCALAPPDATA%\CodexUsageBadge`, adds a background Startup shortcut, and does not require administrator privileges.

## What happens on the next Codex launch

The background helper watches for one new foreground Codex window that has not received input. It can request a normal exit and reopen it with the badge’s local connection. The window may briefly disappear and return.

It skips the attempt when you have already clicked, typed, scrolled, opened multiple instances, launched with a file or link, already use the local port, or decline the normal exit request. It never force-closes Codex.

For Microsoft Store installs, the helper uses Windows app activation rather than directly executing a protected `WindowsApps` executable.

## Commands in the extracted folder

| File | Purpose |
| --- | --- |
| `START-HERE.cmd` | The recommended installer entry point. |
| `Install.cmd` | Install or update the badge. |
| `Status.cmd` | Show the worker, startup monitor, and current connection state. |
| `Launch.cmd` | Guardedly restart one open Codex window with the badge connection, including Microsoft Store installs. |
| `Uninstall.cmd` | Remove the badge, its Startup shortcut, and its local UI settings. |

## Requirements

- Windows 10 or Windows 11.
- A signed-in Codex desktop app that includes the Codex CLI.
- Node.js 24+ with `node:sqlite`. The installer first looks for the runtime bundled with Codex, then for a system Node installation.
- A native Windows session. WSL and remote sessions cannot read the Windows session database.

The scripts use `ExecutionPolicy Bypass` for that process only. They do not alter the registry or your organization’s PowerShell policy. The release is not code-signed; contact your administrator if device policy blocks unsigned scripts.

## Optional custom paths

Supply only the values you need to override:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\manage-windows.ps1 -Action Install -AppExe 'D:\Apps\Codex\Codex.exe' -NodeExe 'D:\Tools\nodejs\node.exe' -CodexBin 'D:\Apps\Codex\resources\codex.exe' -CodexHome 'D:\CodexData'
```

`CodexHome` must be the data directory used by the desktop app, or usage and Token information may be unavailable.

## Troubleshooting

- **No badge after launch:** run `Status.cmd`, fully quit Codex, reopen it from the normal icon, and wait before interacting.
- **Node or CLI not found:** open Codex once; otherwise install Node.js 24 LTS or provide the matching explicit path.
- **Worker did not take over:** `skipped-active-or-background` means the window was already active or used; `quit-refused` means Codex rejected the normal exit request; `skipped-cooldown` prevents retry loops for two minutes. With exactly one Codex window open, run `Launch.cmd` for a guarded manual recovery.
- **Usage unavailable:** confirm that the desktop app and CLI use the same signed-in account and data directory.
- **Gray Token dot:** the current session has no local record, or it is a WSL, remote, or cloud session.

Uninstall keeps your Codex app, account, and chats intact. The installer retains named backup folders such as `CodexUsageBadge.backup-*` and `CodexUsageBadge.uninstalled-*`; remove them yourself when they are no longer needed.
