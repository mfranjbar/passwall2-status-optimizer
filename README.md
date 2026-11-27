# Passwall2 Status Optimizer

[![OpenWrt](https://img.shields.io/badge/platform-OpenWrt%20%2F%20ImmortalWrt-00A86B?logo=openwrt&logoColor=white)](https://openwrt.org/)
[![Passwall2](https://img.shields.io/badge/target-Passwall2-2563EB)](https://github.com/xiaorouji/openwrt-passwall)
[![Shell](https://img.shields.io/badge/shell-POSIX%20sh-4EAA25?logo=gnubash&logoColor=white)](https://www.shellcheck.net/)
[![License](https://img.shields.io/badge/license-MIT-informational)](LICENSE)

A small, reversible patch for the Passwall2 LuCI status page. It staggers the three connectivity checks and routes only the YouTube and X checks through the router's existing local SOCKS5 endpoint.

> **Timing is intentional and fixed:** Arvan at **3 seconds**, YouTube at **4 seconds**, and X at **5 seconds** after the status page loads. These are absolute start offsets, not three separate delays measured from page load.

## Contents

- [Features](#features)
- [Exact test schedule](#exact-test-schedule)
- [Routing behavior](#routing-behavior)
- [Compatibility](#compatibility)
- [Requirements](#requirements)
- [Install](#install)
- [Uninstall and restore](#uninstall-and-restore)
- [Backups and recovery](#backups-and-recovery)
- [What the scripts change](#what-the-scripts-change)
- [Safety model](#safety-model)
- [Troubleshooting](#troubleshooting)
- [Technical notes](#technical-notes)

## Features

- Staggers the automatic Passwall2 status checks to avoid launching all three at once.
- Keeps the exact Flint 2 reference schedule: **3000 / 4000 / 5000 ms**.
- Keeps Arvan direct.
- Sends only the YouTube and X status checks through SOCKS5 at `127.0.0.1:1070`.
- Uses URL host matching before adding the proxy argument; unrelated checks are not proxied.
- Shell-quotes the URL before passing it to the shell.
- Preserves the AX3600 controller's `Mozilla/5.0` curl user-agent when that variant is detected.
- Makes dated backups of both original files before replacing either one.
- Supports repeat execution: a complete, valid installation is detected and left unchanged.
- Includes a paired uninstall script that restores the original two files from the installation backup.

## Exact test schedule

The status page starts the checks at these offsets after its JavaScript sequence is scheduled:

| Check | Start offset | Timer value |
|---|---:|---:|
| Arvan Cloud | +3 seconds | `3000 ms` |
| YouTube | +4 seconds | `4000 ms` |
| X (Twitter) | +5 seconds | `5000 ms` |

Implementation: the first timer is `3000 ms`; the nested timers each add `1000 ms`. Do not change these values if the goal is to keep the same behavior as the verified Flint 2 status page.

## Routing behavior

| Status check | Route |
|---|---|
| Arvan Cloud | Direct |
| YouTube (`www.youtube.com`) | SOCKS5 `127.0.0.1:1070` |
| X (`x.com`) | SOCKS5 `127.0.0.1:1070` |

The proxy endpoint is expected to be provided by the user's existing Passwall2/Xray setup. This project does not start a proxy service or alter its configuration.

## Compatibility

The installer targets the standard Passwall2 LuCI file locations used by OpenWrt/ImmortalWrt:

- GL.iNet Flint 2 / GL-MT6000
- Xiaomi AX3600

The controller patch recognizes the supported single-line `curl` assignment inside `connect_status()`, including the AX3600 form that adds `-A "Mozilla/5.0"`. It refuses to patch an unknown function layout, or if it cannot identify exactly one candidate curl assignment inside that function.

Other router models or Passwall2 forks may use different file paths or controller code. They are not assumed compatible. The installer will stop rather than guess.

## Requirements

- OpenWrt or ImmortalWrt with Passwall2 installed.
- Root shell access.
- `wget`, `awk`, `grep`, `cp`, `mv`, `cmp`, and standard BusyBox/POSIX utilities.
- Existing SOCKS5 listener at `127.0.0.1:1070` if proxied YouTube/X checks are expected to work.
- Network access to GitHub and the status-page source URL used by the installer.

No package manager operation is required. The scripts do not run `opkg`, `apk`, or feed updates.

## Install

Run this as **root** on the router:

```sh
wget -O /tmp/pwso-install.sh https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/install.sh &&
sh /tmp/pwso-install.sh
```

The installer performs these steps:

1. Checks root access, OpenWrt, and the two expected Passwall2 files.
2. Downloads and validates the status-page base.
3. Checks the controller structure and confirms there is exactly one supported curl assignment inside `connect_status()`.
4. Builds patched copies in temporary files and validates the expected sequence and proxy guards.
5. Creates a unique backup of both original files.
6. Replaces only the two target files and verifies the result.
7. Attempts to restore the original pair if a replacement or final verification fails.

On success, refresh the Passwall2 status page in LuCI. The installer does not restart services.

### Re-running the installer

Run the same install command again. If both files contain the expected complete patch, the installer reports that it is already installed and makes no changes. If it detects a partial or inconsistent state, it stops and asks for recovery instead of attempting an automatic overwrite.

## Uninstall and restore

Run this as **root**:

```sh
wget -O /tmp/pwso-uninstall.sh https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/uninstall.sh &&
sh /tmp/pwso-uninstall.sh
```

The uninstaller:

- Requires the optimizer markers to exist in both target files.
- Selects the newest complete backup containing both original files.
- Restores the original `status.htm` and `passwall2.lua`.
- Verifies that the optimizer markers are no longer present.
- Retains all backup directories; it does not delete backups.
- Does not restart Passwall2, uhttpd, or any other service.

Refresh the Passwall2 LuCI page after it completes.

## Backups and recovery

Every successful installation creates a unique backup directory under:

```text
/root/backup/passwall2-status-optimizer/
```

Each backup contains:

```text
status.htm.before
passwall2.lua.before
```

To list available backups:

```sh
ls -lt /root/backup/passwall2-status-optimizer/
```

The uninstaller chooses the newest complete backup directory. Keep the backup directory if you may want to restore the optimizer later.

If the installer reports a partial installation, do not delete markers or edit the Lua file manually. Inspect the backups first and use the matching original pair for recovery. The scripts intentionally stop on ambiguous states.

## What the scripts change

Only these two files:

```text
/usr/lib/lua/luci/view/passwall2/global/status.htm
/usr/lib/lua/luci/controller/passwall2.lua
```

The status page is downloaded from:

`https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm`

The controller change is limited to the curl command inside `connect_status()`. The URL is shell-quoted, and the SOCKS5 argument is added only when the URL host is the expected YouTube or X host.

## Safety model

- **Backup first:** both original files are copied and verified before replacement.
- **Narrow patch scope:** only the two Passwall2 LuCI files listed above are replaced.
- **No blind search-and-replace:** the controller function and candidate curl line are checked before patching.
- **Staged validation:** temporary patched files are checked before the originals are touched.
- **Rollback attempt:** if the second replacement or post-install verification fails, the installer attempts to restore both originals.
- **Conservative failure:** unsupported or partial states cause an error and no speculative patch.
- **No service restart:** no service is restarted by install or uninstall.
- **No system configuration changes:** no UCI settings, DNS, firewall, routing rules, packages, feeds, kernel settings, or Passwall2 core/Xray configuration are changed.

As with any router-side file modification, keep a separate copy of important configuration and do not interrupt power during file replacement.

## Troubleshooting

### `Passwall2 status page not found`

Passwall2 may not be installed, or the firmware uses a different LuCI path. The installer does not create substitute files.

### `Controller source ... not supported`

The installed Passwall2 controller differs from the recognized `connect_status()` layout. No original file is changed by this validation failure. Do not force the patch; inspect the function and adapt the installer for that exact source variant.

### `Partial installation detected`

Only one target file has the optimizer marker, or the pair is inconsistent. The installer stops to avoid mixing versions. Check the dated backup directory before taking further action.

### YouTube or X still fails

Confirm that Passwall2's local SOCKS5 listener is actually available at `127.0.0.1:1070`. This project does not create or repair that listener. Arvan is intentionally tested directly.

### Changes do not appear in LuCI

Refresh the Passwall2 status page. The scripts do not restart LuCI or other services.

## Technical notes

- The measured `time_appconnect` value is curl's TLS connection timing field; it is not a full-page load measurement.
- `--connect-timeout 3` remains unchanged. This is curl's connection timeout, not a total request deadline.
- The timer offsets determine when each check starts; they do not guarantee that the previous network request has completed.
- The controller patch routes by the submitted URL host. Only the exact supported YouTube and X URL patterns receive the SOCKS5 argument.
- The installer is intentionally conservative. A new Passwall2 source variant should be inspected and explicitly supported rather than patched with a broad replacement.

---

**Project:** [mfranjbar/passwall2-status-optimizer](https://github.com/mfranjbar/passwall2-status-optimizer)
