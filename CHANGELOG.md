# Changelog

## Windows 0.11.10

- Fixed confirmed restart rejecting the verified Codex process after it was already launched with the Badge debug port.

## Windows 0.11.9

- Fixed confirmed restart refusing to close Codex when its existing Badge connection occupied the local debug port.

## Windows 0.11.8

- Fixed confirmed menu restart being skipped when the Badge was already connected to Codex.

## Windows 0.11.7

- Made the menu's confirmed restart close the one verified Codex process before relaunching it with the Badge connection.

## Windows 0.11.6

- Replaced the separate Windows command files with one `Codex Usage Badge.cmd` menu.
- Added an explicit save-work confirmation before a post-install Codex restart.

## Windows 0.11.5

- Made `Launch.cmd` a guarded, explicit recovery path for Microsoft Store Codex when automatic startup cannot attach.
- Kept automatic startup unchanged: it still refuses to take over used, background, or multiple windows.

## Windows 0.11.4

- Fixed installation from the slim package by removing the obsolete `README-Windows.md` copy step.

## Windows 0.11.3 (pre-release)

- Kept `START-HERE.cmd` and `Install.cmd` in one terminal window.
- Replaced the generic pause prompt with “Press any key to exit.”

## Windows 0.11.2 (pre-release)

- Prevented `Launch.cmd` from directly starting Microsoft Store Codex, which loses package identity.
- Clarified that Store installations must reopen Codex from its normal icon so the background helper can use Windows app activation.

## Windows 0.11.1 (pre-release)

- Added `START-HERE.cmd` as the recommended one-click Windows installer entry point.
- Translated the release documentation and Windows installation flow to English.
- Kept the compact English UI redesign from Windows 0.10.1.

## Windows 0.10.1 (pre-release)

- Redesigned the badge for a quieter sidebar with compact usage cards and small circular Token markers.
- Switched badge labels, tooltips, project-color controls, and runtime messages to English.
- Added English K, M, and B Token formatting.

## macOS 0.9.2 (pre-release)

- Fixed GPT sidebar Token marker wrapping and alignment with chat titles.
- Preserved row height, metadata, long-title truncation, and secondary text across light and dark themes.
- Added layout regression coverage for both sidebar modes and multiple widths.

## Windows 0.10.0 (pre-release)

- Added normal-icon startup and guarded automatic relaunch for new, untouched foreground windows.
- Used Windows app activation for Microsoft Store installs instead of direct protected executable launches.
- Added raw-input safety checks, startup diagnostics, cooldown protection, and rollback coverage.

## 0.9.1

- Improved light-theme usage rings and Token/project-color contrast.

## 0.9.0

- Added automatic startup for macOS and safer launch guards.

## 0.8.0

- First public pre-release with usage rings, project colors, and Token indicators.
