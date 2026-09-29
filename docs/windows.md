# Windows guide

## One-file menu

1. Download and fully extract the Windows ZIP.
2. Open the extracted folder and double-click **`Codex Usage Badge.cmd`**.
3. Open and sign in to Codex once if you have not already.
4. Choose **Install or update**.
5. Save your Codex work, then type `C` when the menu asks whether it can restart Codex.

The installer uses the current user account only. It installs to `%LOCALAPPDATA%\CodexUsageBadge`, adds a background Startup shortcut, and does not require administrator privileges.

## What happens during restart

After the user saves work and types `C`, the menu closes one verified Codex process and reopens Codex with the Badge’s local connection. The window may briefly disappear and return.

It refuses the attempt when multiple Codex windows are open or the local port is already in use. The confirmed menu action closes only the one verified Codex process; automatic background startup never force-closes Codex.

For Microsoft Store installs, the helper uses Windows app activation rather than directly executing a protected `WindowsApps` executable.

## Menu actions

| Menu option | Purpose |
| --- | --- |
| **Install or update** | Install or update the Badge, then prompt before restart. |
| **Restart Codex with Badge** | Close and relaunch one verified Codex window with the Badge connection, including Microsoft Store installs. |
| **Check status** | Show the worker, startup monitor, and current connection state. |
| **Uninstall** | Remove the Badge, its Startup shortcut, and its local UI settings. |
| **Exit** | Close the menu without changing anything. |

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

- **No badge after launch:** choose **Check status**, then save work and choose **Restart Codex with Badge**.
- **Node or CLI not found:** open Codex once; otherwise install Node.js 24 LTS or provide the matching explicit path.
- **Restart was refused:** close extra Codex windows, leave one window open, then choose **Restart Codex with Badge**.
- **Usage unavailable:** confirm that the desktop app and CLI use the same signed-in account and data directory.
- **Gray Token dot:** the current session has no local record, or it is a WSL, remote, or cloud session.

Uninstall keeps your Codex app, account, and chats intact. The installer retains named backup folders such as `CodexUsageBadge.backup-*` and `CodexUsageBadge.uninstalled-*`; remove them yourself when they are no longer needed.
