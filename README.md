# Passwall2 Status Optimizer

[![Platform](https://img.shields.io/badge/platform-OpenWrt%20%7C%20ImmortalWrt-blue)](https://openwrt.org/)
[![Shell](https://img.shields.io/badge/shell-BusyBox%20ash-lightgrey)](https://www.busybox.net/)

A lightweight, reversible installer that optimizes the Passwall2 LuCI status-page connectivity checks while preserving the router's existing configuration.

> **Default sequence:** Arvan starts after **3 seconds**, YouTube after **4 seconds**, and X (Twitter) after **5 seconds**.

## Contents

- [Features](#features)
- [Execution sequence](#execution-sequence)
- [Requirements](#requirements)
- [Installation](#installation)
- [Uninstallation](#uninstallation)
- [Backup and recovery](#backup-and-recovery)
- [Verification](#verification)
- [Scope and safety](#scope-and-safety)
- [Compatibility and troubleshooting](#compatibility-and-troubleshooting)

## Features

- Sequential Arvan, YouTube, and X (Twitter) connectivity checks.
- Uses the existing SOCKS5 endpoint `127.0.0.1:1070` for YouTube, X, and Twitter checks.
- Downloads the status page from the specified upstream source.
- Creates and verifies backups of both affected files before editing.
- Attempts automatic restoration if installation fails after backup creation.
- Includes an uninstaller that restores the exact originals from the last successful installation.
- Retains dated backups; installation and uninstallation do not delete them.
- Does not restart Passwall2 or other services.

## Execution sequence

The default delays are **3000 / 1000 / 1000 milliseconds**, in nested timer order:

| Check | Delay | Expected start |
|---|---:|---:|
| Arvan | 3000 ms initial delay | +3 seconds |
| YouTube | 1000 ms after Arvan starts | +4 seconds |
| X (Twitter) | 1000 ms after YouTube starts | +5 seconds |

The equivalent JavaScript timer structure is:

```js
setTimeout(function() {
    check_connect('arvan', 'https://www.arvancloud.ir/fa');
    setTimeout(function() {
        check_connect('youtube', 'https://www.youtube.com/');
        setTimeout(function() {
            check_connect('twitter', 'https://x.com/');
        }, 1000);
    }, 1000);
}, 3000);
```

These are sequential start delays, not test timeouts. The installer applies these defaults automatically; no timing input is required.

## Requirements

- OpenWrt or ImmortalWrt.
- Passwall2 installed with its standard LuCI file paths.
- Root access.
- The expected controller curl assignment must exist exactly once.

## Installation

Run the following command as root:

```sh
wget -O /tmp/pwso-install.sh https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/install.sh && sh /tmp/pwso-install.sh
```

The installer:

1. Checks the environment and required files.
2. Confirms the expected controller curl line is present exactly once.
3. Creates a dated backup of both original files and verifies the backup.
4. Downloads the upstream status page to its target path:
   `https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm`
5. Applies the specified controller curl adjustment.
6. Inserts the sequential status checks with the default timing.
7. Verifies the resulting files.

Refresh the Passwall2 LuCI status page after installation. No service restart is performed.

## Uninstallation

Run as root:

```sh
wget -O /tmp/pwso-uninstall.sh https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/uninstall.sh && sh /tmp/pwso-uninstall.sh
```

The uninstaller restores both original files from the backup recorded by the last successful installation. It retains all backup directories.

## Backup and recovery

Backups are stored under:

```text
/root/backup/passwall2-status-optimizer/
```

Each installation creates a timestamped directory containing:

- `status.htm.before`
- `passwall2.lua.before`

The `active-backup` file identifies the backup associated with the current successful installation.

If installation fails after backup creation, the installer attempts to restore both original files automatically. Keep the backup directory intact until you have confirmed the router is working as expected.

## Verification

To inspect the installed timing without changing anything:

```sh
F='/usr/lib/lua/luci/view/passwall2/global/status.htm'
grep -n -A 9 "check_connect('arvan','https://www.arvancloud.ir/fa')" "$F"
```

The nested timer values should appear in this order:

```js
}, 1000);  // X delay after YouTube
}, 1000);  // YouTube delay after Arvan
}, 3000);  // initial Arvan delay
```

## Scope and safety

The installer modifies only these two files:

- `/usr/lib/lua/luci/view/passwall2/global/status.htm`
- `/usr/lib/lua/luci/controller/passwall2.lua`

It does **not**:

- Change UCI configuration.
- Modify DNS, firewall, routing, or network settings.
- Install or remove packages.
- Add controller imports, helper functions, markers, or routing logic.
- Change the SOCKS5 endpoint from `127.0.0.1:1070`.
- Restart Passwall2, LuCI, or any other service.

The controller adjustment routes YouTube, X, and Twitter URL checks through the existing SOCKS5 endpoint; other URL checks do not use that SOCKS5 option.

## Compatibility and troubleshooting

The scripts expect the standard Passwall2 paths listed above. The installer stops before modifying files if the expected controller curl assignment is missing or appears more than once.

If the status page does not reflect the change, refresh the LuCI page and run the [verification](#verification) command. If you need to revert, use the uninstallation command above.

---

**Repository:** https://github.com/mfranjbar/passwall2-status-optimizer
