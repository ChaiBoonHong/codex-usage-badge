# macOS guide

1. Download and extract the macOS ZIP.
2. Double-click `install.command`.
3. Fully quit Codex with <kbd>⌘</kbd> + <kbd>Q</kbd>, then reopen it from the normal app icon and wait 5–10 seconds.

The installer does not modify the Codex application bundle or its signature. It installs a local helper under `~/Library/Application Support/CodexUsageBadge`.

## Automatic loading

After login, the helper waits for a newly opened, untouched Codex window. It can request one normal exit and reopen the app with the badge connection. Typing, clicking, scrolling, switching apps, an already-open work window, or a declined exit request cancels that attempt. It never force-quits Codex and waits at least two minutes before another attempt.

## Requirements

The installer finds `Codex.app` or a `ChatGPT.app` bundle containing Codex. It prefers the bundled Node.js runtime. If no compatible runtime is available, install [Node.js 24 LTS](https://nodejs.org/en/download).

Use `bash ./install.command` if Finder blocks the script. Run `status.command` for diagnostics or `uninstall.command` to remove the badge.

## Common issues

- **Nothing appears after reopening:** fully quit Codex, reopen it from the normal icon, and wait before interacting.
- **Usage unavailable:** ensure the app and CLI use the same account. API-key sign-in may not provide subscription usage.
- **Token dot is gray:** the current session has no local record, or it is a cloud, SSH, or WSL session.
- **An app update broke the badge:** rerun the installer after the update.
