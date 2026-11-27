# Passwall2 Status Optimizer

A small, reversible installer for the Passwall2 LuCI status page and its connectivity-test controller command.

## What it does

The installer performs the requested operations in this order:

1. **Backs up both original files first**:
   - `/usr/lib/lua/luci/view/passwall2/global/status.htm`
   - `/usr/lib/lua/luci/controller/passwall2.lua`
2. Downloads the upstream status page directly to its final path:
   `https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm`
3. Applies the specified `sed -i` replacement to the controller's `local result = luci.sys.exec...` line. YouTube, X, and Twitter URLs use the existing SOCKS5 endpoint `127.0.0.1:1070`; other URLs do not.
4. Inserts the three sequential status checks immediately before `//]]>`.

No other controller imports, markers, helper functions, controller routing logic, service settings, packages, DNS, firewall, or UCI configuration are added or changed.

## Default timing

The defaults are **3000 / 1000 / 1000 ms sequential delays**:

| Check | Delay from previous step | Start after sequence begins |
|---|---:|---:|
| Arvan | 3000 ms | 3 seconds |
| YouTube | 1000 ms | 4 seconds |
| X (Twitter) | 1000 ms | 5 seconds |

The installer leaves these values as requested. If another timing is needed on a particular router, edit the three timer values in `status.htm` manually after installation.

## Install

Run as root:

```sh
wget -O /tmp/pwso-install.sh https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/install.sh && sh /tmp/pwso-install.sh
```

The installer verifies the expected files and controller curl line, creates and verifies a dated backup of both files, then runs the requested download and edits in order. If an operation fails after the backup, it attempts to restore both originals.

After installation, refresh the Passwall2 LuCI status page. No service restart is performed.

## Uninstall

Run as root:

```sh
wget -O /tmp/pwso-uninstall.sh https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/uninstall.sh && sh /tmp/pwso-uninstall.sh
```

The uninstaller restores both original files from the exact backup recorded by the last successful installation. Backups are retained and are not deleted.

## Backup location

```
/root/backup/passwall2-status-optimizer/
```

Each installation creates a timestamped directory containing:

- `status.htm.before`
- `passwall2.lua.before`

The `active-backup` file identifies the backup belonging to the current installation.

## Scope

Only the two Passwall2 files above are modified. The scripts do not install packages, change UCI, alter DNS/firewall/routing configuration, or restart services.

## Supported environments

OpenWrt / ImmortalWrt with Passwall2 installed and the standard file paths shown above. The controller replacement expects exactly one matching `local result = luci.sys.exec...` curl assignment. If that line is not found exactly once, installation stops before changing files.

## Manual timing adjustment

In `status.htm`, the three values are the timers nested in this order:

```js
}, 1000);  // X delay after YouTube
}, 1000);  // YouTube delay after Arvan
}, 3000);  // initial Arvan delay
```

Change only the numeric values when needed. The default installation does not ask for timing input.

---
Project: https://github.com/mfranjbar/passwall2-status-optimizer
