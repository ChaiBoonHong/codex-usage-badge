# Development and verification

Requirements: Node.js 24+, Python 3.10+, and Playwright Chromium for UI tests. macOS native helpers also require Xcode Command Line Tools.

```bash
npm ci
npx playwright install chromium --only-shell
python3 build.py
npm test
npm run test:privacy
```

Build a Windows-only archive:

```bash
python3 scripts/build_release.py --platform Windows
```

The Windows version comes from `package.json` `windowsVersion`. The builder writes the ZIP and `SHA256SUMS.txt` to `dist/`, uses an allowlist, and replaces the generated agent version inside the Windows archive.

Publish Windows builds as normal GitHub releases. Do not mark them as prereleases unless the user explicitly requests a prerelease.

Run Windows PowerShell checks with `pwsh -File tests/windows.ps1`. The startup bridge check is `powershell -NoProfile -ExecutionPolicy Bypass -File tests/windows-startup-native.ps1`; it uses only a temporary hidden app.

The badge reads Codex usage through the signed-in CLI. Plus plans expose both 5-hour and weekly windows; Pro shows the weekly window. Token totals come from the local session database, include cached input, and are not a current-context measurement.

The UI depends on internal app structure and the local debug interface. Automated tests use fixtures and temporary data only; they do not access a real account.
