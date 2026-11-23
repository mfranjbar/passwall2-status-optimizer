# Passwall2 Status Optimizer

A standalone post-installation patch for OpenWrt Passwall2.

## What it does

1. Downloads the base \`status.htm\` from the requested source:
   \`iranopenwrt/auto/resources/status.htm\`
2. Adds automatic connection checks in this order:
   - Arvan: 3 seconds after the status page script starts
   - YouTube: 1 second after the Arvan check starts
   - X: 1 second after the YouTube check starts
3. Patches Passwall2's \`connect_status()\` handler so only the \`youtube\` and \`twitter\` checks use:
   \`socks5h://127.0.0.1:1070\`
   Arvan and other check types remain direct.
4. Creates a unique dated backup of the existing status page and controller before installing either patched file.
5. Verifies the source structure and patch preconditions. It stops without changing the originals if the local Passwall2 controller does not match the supported source pattern.
6. Is safe to run again: a complete existing installation exits without changing files; a partial installation is rejected.

## Run after Passwall2 is installed

As root on the OpenWrt router:

\`\`\`sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/mfranjbar/passwall2-status-optimizer/main/install.sh)"
\`\`\`

## Files changed

- \`/usr/lib/lua/luci/view/passwall2/global/status.htm\`
- \`/usr/lib/lua/luci/controller/passwall2.lua\`

Backups are stored under:

- \`/root/backup/passwall2-status-optimizer/\`

No package feeds, packages, DNS, firewall, routing, or Passwall2 UCI settings are changed.

## Important

The SOCKS5 listener must be available at \`127.0.0.1:1070\` when the YouTube and X checks run. The installer reports whether it can detect that listener at installation time, but does not enable or reconfigure Passwall2 SOCKS settings.

The installer is deliberately fail-closed: if the downloaded status page or local controller no longer matches the expected structure, it stops rather than applying a guessed patch.

After installation, refresh the Passwall2 LuCI page. If the running web server has cached the controller module, reload the LuCI web service during a suitable maintenance window.
