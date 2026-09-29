# Privacy and security

All badge processing stays on your device. The badge reads subscription usage through the Codex CLI’s existing signed-in state and reads only local session IDs and cumulative Token values. It does not read chat bodies, upload telemetry, or request API keys, cookies, or access tokens.

The startup helper checks process state and recent input timing to avoid interrupting work. It does not record keystrokes, screenshots, mouse coordinates, or input content. It only requests a normal exit for one new, untouched foreground instance and never uses forced Restart Manager shutdown or global keyboard injection.

The badge uses the local debugging endpoint `127.0.0.1:39222`. Other programs on your computer that can reach that port may be able to control Codex, so never forward the port to a network.

Release archives use an allowlist and are scanned for credentials, personal paths, and data files. They contain project code, compiled startup helpers, documentation, artwork, and checksums—not Codex binaries or user data.

Report security issues through GitHub private vulnerability reporting. Do not include credentials, chats, or full diagnostic logs in a public issue.
