# Passwall2 Status Optimizer

A standalone, guarded installer for the requested Passwall2 status-page sequence and test routing.

## What it changes

Only these two files are replaced:

- `/usr/lib/lua/luci/view/passwall2/global/status.htm`
- `/usr/lib/lua/luci/controller/passwall2.lua`

The installer downloads the status-page base from:

`https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm`

It then applies this sequence after the status page loads:

1. Arvan starts at **+3000 ms**.
2. YouTube starts **1000 ms later** (**+4000 ms**).
3. X starts **1000 ms later** (**+5000 ms**).

Only the YouTube and X connection checks are routed through the fixed SOCKS5 endpoint `127.0.0.1:1070`. Arvan remains a direct check.

## Install

Run as root on the OpenWrt router after Passwall2 is installed:

```sh
wget -qO- https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/install.sh | sh
```

No package or feed update is performed.

## Safety

- Creates a unique, dated backup of both original files under `/root/backup/passwall2-status-optimizer/`.
- Validates the downloaded status-page structure and the controller's `connect_status()` function before changing either original file. It supports both the standard curl form and the AX3600 form that includes `-A "Mozilla/5.0"`.
- Builds and verifies staged copies in the destination directories, preserving the original file ownership and permissions.
- Replaces the two files atomically and attempts rollback if the second replacement or final verification fails.
- A complete existing installation is detected and left unchanged. A partial or inconsistent installation is rejected.
- Does not change UCI settings, DNS, firewall, routing, packages, feeds, or running services.
- The controller patch is limited to the single curl assignment inside `connect_status()`. It routes by the requested URL host (YouTube and `x.com` only), preserves the AX3600 Mozilla user-agent when present, and shell-quotes the URL. If the function shape is not recognized or contains zero/multiple candidate curl assignments, installation stops without patching either file.

After installation, refresh the Passwall2 status page in LuCI.
