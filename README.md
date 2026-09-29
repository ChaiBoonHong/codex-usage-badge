# Codex Usage Badge

> A small, local-first status layer for the Codex desktop app.

[![Windows release](https://img.shields.io/github/v/release/ChaiBoonHong/codex-usage-badge?filter=*-windows&label=Windows&color=0f8b6d)](https://github.com/ChaiBoonHong/codex-usage-badge/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-4c78a8.svg)](LICENSE)
[![Local only](https://img.shields.io/badge/data-local%20only-0f8b6d)](SECURITY.md)

![Codex Usage Badge preview](assets/cover.png)

**Usage at a glance. Projects at a glance. No account credentials required.**

| Jump to | What you will find |
| --- | --- |
| [Install on Windows](#install-on-windows) | The current Windows download and first-run steps |
| [What it adds](#what-it-adds) | Usage, project colors, and Token indicators |
| [Privacy and safety](#privacy-and-safety) | Exactly what stays local and why |
| [Build from source](#build-from-source) | Reproducible build and test commands |

## What it adds

| Feature | In the Codex sidebar |
| --- | --- |
| **Usage card** | Compact 5-hour and weekly usage rings. Hover for reset time and available reset credits. |
| **Project colors** | Pick a color from a project’s context menu; it stays with that local project. |
| **Token dots** | Small, unobtrusive circular markers. Hover for cumulative chat-token totals. |

<details>
<summary><strong>Why the new design is quieter</strong></summary>

The badge deliberately avoids a second navigation system. Usage is a compact card near the existing rail footer, and Token information is a small colored dot instead of a large square. Labels, menus, tooltips, and runtime messages are English-first.

</details>

<details>
<summary><strong>How colors and Token dots work</strong></summary>

- Right-click a project or use <kbd>Shift</kbd> + <kbd>F10</kbd> to choose its color.
- Token dots show a local cumulative total. Their shades increase from gray through blue as the total grows.
- The total includes cached input and is not a measurement of the current context window.

</details>

## Install on Windows

1. Download [**CodexUsageBadge-Windows-0.11.2.zip**](https://github.com/ChaiBoonHong/codex-usage-badge/releases/download/v0.11.2-windows/CodexUsageBadge-Windows-0.11.2.zip).
2. Extract the ZIP completely.
3. Open and sign in to the Codex desktop app once.
4. Run `START-HERE.cmd` from the extracted folder.
5. Fully quit Codex, including its tray process, then reopen it from the normal Codex icon.

The Windows helper waits for a new, untouched foreground launch. It may briefly close and reopen Codex once to add its local connection. It does not take over windows that are already in use.

Need help? Open [Windows instructions](docs/windows.md) or run `Status.cmd` from the extracted folder.

## Privacy and safety

The badge is a local integration, not a hosted service.

- It reads usage through the already signed-in Codex CLI.
- It reads only local session IDs and cumulative Token values; it does not read chat bodies.
- It does not request API keys, cookies, or access tokens.
- It uses `127.0.0.1:39222` only. Do not expose or forward that port.

Read the full [security and privacy notes](SECURITY.md).

## Compatibility

| Requirement | Why |
| --- | --- |
| Windows 10 or 11 | Windows desktop app and local activation support |
| Signed-in Codex desktop app | Supplies the local CLI and account context |
| Node.js 24+ | Needed for `node:sqlite`; the installer first tries the bundled runtime |
| Native Windows session | WSL and remote sessions cannot read the local Windows session database |

## Build from source

```powershell
npm ci
npx playwright install chromium --only-shell
npm test
npm run test:privacy
python scripts/build_release.py --platform Windows
```

The release builder writes the ZIP and `SHA256SUMS.txt` to `dist/`. It uses an allowlist and does not package your Codex installation, chats, credentials, or local data.

## Project map

```text
src/       Badge UI, formatting, local data readers, and CDP injection
windows/   Windows installer, lifecycle worker, and Store-app activation
startup/   Guarded startup controller and native bridge
tests/     Unit, layout, lifecycle, and release-safety checks
```

## Status

- **Windows v0.11.2** — Store-safe launch behavior, English installer, documentation, and compact sidebar layout.
- **macOS v0.9.2** — Existing release remains available; it is not changed by this Windows release.

This is an independent MIT-licensed project and is not affiliated with OpenAI.
