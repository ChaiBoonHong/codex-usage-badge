# Security and privacy

This unofficial tool connects to the desktop app over a loopback debugging port. It does not upload data, collect telemetry, bundle credentials, or read conversation bodies. It reads only visible thread IDs and cumulative token counts from the local SQLite database. Quota is obtained through the installed Codex CLI using the user's existing account.

The debugger allows control of the app's renderer. Keep port 39222 local; never forward it to another host. Other local software may access the same debugger. Use only on a trusted machine. The desktop application's own connections are outside this tool's control.

Folder colors are stored in localStorage. Runtime paths, status and logs remain on the user's device. Diagnostic output can contain local paths and quota values; redact it before sharing. The project never asks you to paste access tokens, cookies or API keys.

Release packages contain only allowlisted code, documentation, launch scripts, the license and checksums. The build excludes user data, screenshots, logs, installation receipts, original private bundles and third-party binaries. `scripts/audit_release.py` checks tracked sources and archives for common secrets and personal paths; automated scanning is supplemented by a manual review before publishing.

For a vulnerability, use GitHub private vulnerability reporting when available. Do not place credentials or private conversation data in a public issue. Include a minimal synthetic reproduction.
