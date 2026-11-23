#!/bin/sh
# Passwall2 Status Optimizer
# Installs iranopenwrt/auto status.htm and applies guarded timing/SOCKS5 patches.
set -eu
umask 077

STATUS_URL="https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm"
STATUS_FILE="/usr/lib/lua/luci/view/passwall2/global/status.htm"
CONTROLLER_FILE="/usr/lib/lua/luci/controller/passwall2.lua"
BACKUP_ROOT="/root/backup/passwall2-status-optimizer"
WORK="/tmp/passwall2-status-optimizer.$$"
STATUS_MARKER="PWSO_AUTO_TEST_SEQUENCE_V1"
CONTROLLER_MARKER="PWSO_SOCKS_ROUTE_V1"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT HUP INT TERM

[ "$(id -u)" = "0" ] || die "Run as root."
[ -x /bin/sh ] || die "/bin/sh is unavailable."
[ -f /etc/openwrt_release ] || die "This script is intended for OpenWrt."
command -v wget >/dev/null 2>&1 || die "wget is required."
command -v awk >/dev/null 2>&1 || die "awk is required."
command -v grep >/dev/null 2>&1 || die "grep is required."
command -v cmp >/dev/null 2>&1 || die "cmp is required."
command -v cp >/dev/null 2>&1 || die "cp is required."
command -v mv >/dev/null 2>&1 || die "mv is required."

[ -f "$CONTROLLER_FILE" ] || die "Passwall2 controller not found: $CONTROLLER_FILE"
mkdir -p "$(dirname "$STATUS_FILE")" "$BACKUP_ROOT" "$WORK"

# Refuse mixed/partial installations; never stack patches.
status_done=0
controller_done=0
grep -Fq "$STATUS_MARKER" "$STATUS_FILE" 2>/dev/null && status_done=1 || true
grep -Fq "$CONTROLLER_MARKER" "$CONTROLLER_FILE" 2>/dev/null && controller_done=1 || true
if [ "$status_done" -eq 1 ] && [ "$controller_done" -eq 1 ]; then
    ok "Optimizer is already installed; no files changed."
    exit 0
fi
if [ "$status_done" -eq 1 ] || [ "$controller_done" -eq 1 ]; then
    die "Partial or inconsistent installation detected. No files changed; inspect the files and restore a matching backup."
fi

info "Downloading the requested status.htm base from iranopenwrt/auto..."
wget -q -O "$WORK/status.base" "$STATUS_URL" || die "Download failed."
[ -s "$WORK/status.base" ] || die "Downloaded status.htm is empty."
grep -Fq "function check_connect(type, url)" "$WORK/status.base" || die "Downloaded status.htm does not match the expected source structure."
grep -Fq "check_connect('arvan', 'https://www.arvancloud.ir/fa')" "$WORK/status.base" || die "Arvan test entry not found."
grep -Fq "check_connect('youtube', 'https://www.youtube.com/')" "$WORK/status.base" || die "YouTube test entry not found."
grep -Fq "check_connect('twitter', 'https://x.com/')" "$WORK/status.base" || die "X test entry not found."
[ "$(grep -Fxc '//]]>' "$WORK/status.base" || true)" -eq 1 ] || die "Expected exactly one JavaScript closing marker in status.htm."

# This patch is intentionally tied to the known Passwall2 connect_status() curl line.
OLD_CURL="	local result = luci.sys.exec('curl --connect-timeout 3 -o /dev/null -I -sk -w \"%{http_code}:%{time_appconnect}\" ' .. url)"
[ "$(grep -Fxc "$OLD_CURL" "$CONTROLLER_FILE" || true)" -eq 1 ] || die "Passwall2 controller differs from the supported connect_status() source. No files changed."
grep -Fq 'local util = require "luci.util"' "$CONTROLLER_FILE" || die "Controller does not load luci.util; refusing an unsafe patch."
[ "$(grep -Fc 'function connect_status()' "$CONTROLLER_FILE" || true)" -eq 1 ] || die "Expected exactly one connect_status() function."

cat > "$WORK/status.fragment" <<'EOF'
		/* PWSO_AUTO_TEST_SEQUENCE_V1 */
		// Arvan at +3000 ms; YouTube +1000 ms later; X +1000 ms after YouTube.
		setTimeout(function() {
			check_connect('arvan', 'https://www.arvancloud.ir/fa');
			setTimeout(function() {
				check_connect('youtube', 'https://www.youtube.com/');
				setTimeout(function() {
					check_connect('twitter', 'https://x.com/');
				}, 1000);
			}, 1000);
		}, 3000);
EOF

cat > "$WORK/controller.fragment" <<'EOF'
	-- PWSO_SOCKS_ROUTE_V1
	local check_type = http.formvalue("type") or ""
	local proxy_args = ""
	if check_type == "youtube" or check_type == "twitter" then
		proxy_args = " --socks5-hostname 127.0.0.1:1070"
	end
	local result = luci.sys.exec("curl" .. proxy_args .. " --connect-timeout 3 -o /dev/null -I -sk -w '%{http_code}:%{time_appconnect}' " .. util.shellquote(url or ""))
EOF

# Build both patched files in the work directory; originals remain untouched.
awk -v fragment="$WORK/status.fragment" '
$0 == "//]]>" {
    count++
    while ((getline line < fragment) > 0) print line
    close(fragment)
}
{ print }
END { if (count != 1) exit 41 }
' "$WORK/status.base" > "$WORK/status.new" || die "Could not safely patch status.htm."

awk -v target="$OLD_CURL" -v fragment="$WORK/controller.fragment" '
$0 == target {
    count++
    while ((getline line < fragment) > 0) print line
    close(fragment)
    next
}
{ print }
END { if (count != 1) exit 42 }
' "$CONTROLLER_FILE" > "$WORK/controller.new" || die "Could not safely patch the controller."

grep -Fq "$STATUS_MARKER" "$WORK/status.new" || die "Status patch validation failed."
grep -Fq "$CONTROLLER_MARKER" "$WORK/controller.new" || die "Controller patch validation failed."
[ "$(grep -Fc "setTimeout(function()" "$WORK/status.new")" -ge 3 ] || die "Timing sequence validation failed."
grep -Fq -- "--socks5-hostname 127.0.0.1:1070" "$WORK/controller.new" || die "SOCKS5 route validation failed."
grep -Fq 'check_type == "youtube" or check_type == "twitter"' "$WORK/controller.new" || die "SOCKS5 target validation failed."
grep -Fq 'util.shellquote(url or "")' "$WORK/controller.new" || die "URL shell-quoting validation failed."

# Keep a unique, dated backup; never overwrite an earlier backup.
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_ROOT/$stamp"
n=0
while [ -e "$backup" ]; do
    n=$((n + 1))
    backup="$BACKUP_ROOT/$stamp-$n"
done
mkdir -p "$backup"
if [ -f "$STATUS_FILE" ]; then
    cp -p "$STATUS_FILE" "$backup/status.htm.before"
else
    : > "$backup/status.htm.was-absent"
fi
cp -p "$CONTROLLER_FILE" "$backup/passwall2.lua.before"
cmp -s "$CONTROLLER_FILE" "$backup/passwall2.lua.before" || die "Controller backup verification failed."
if [ -f "$STATUS_FILE" ]; then
    cmp -s "$STATUS_FILE" "$backup/status.htm.before" || die "Status backup verification failed."
fi

# Transaction: install status first, then controller; restore both on any failure.
rollback() {
    warn "Installation failed; restoring original files."
    if [ -f "$backup/status.htm.before" ]; then
        cp -p "$backup/status.htm.before" "$STATUS_FILE" || warn "Could not restore status.htm automatically."
    elif [ -f "$backup/status.htm.was-absent" ]; then
        rm -f "$STATUS_FILE"
    fi
    cp -p "$backup/passwall2.lua.before" "$CONTROLLER_FILE" || warn "Could not restore passwall2.lua automatically."
}
if ! cp -p "$WORK/status.new" "$STATUS_FILE"; then
    rollback
    die "Could not install status.htm."
fi
if ! cp -p "$WORK/controller.new" "$CONTROLLER_FILE"; then
    rollback
    die "Could not install passwall2.lua."
fi

# Final content verification; roll back if either installed file is not exact.
if ! cmp -s "$WORK/status.new" "$STATUS_FILE" || ! cmp -s "$WORK/controller.new" "$CONTROLLER_FILE"; then
    rollback
    die "Final verification failed; original files were restored."
fi

ok "Passwall2 status optimizer installed."
info "Backup directory: $backup"
info "Timing: Arvan +3s, YouTube +4s, X +5s after page script start."
info "Routing: YouTube and X checks use SOCKS5 127.0.0.1:1070; Arvan remains direct."
if [ -r /proc/net/tcp ] && ! awk 'NR > 1 && $2 ~ /^0100007F:043A$/ && $4 == "0A" { found=1 } END { exit !found }' /proc/net/tcp; then
    warn "No IPv4 listener was detected on 127.0.0.1:1070 at install time. Enable/start the intended Passwall2 SOCKS listener before relying on YouTube/X checks."
else
    ok "SOCKS listener check passed or could not be determined from /proc/net/tcp."
fi
info "No package feeds, packages, DNS, firewall, routing, or Passwall2 settings were changed."
info "Refresh the LuCI Passwall2 page. If the controller is cached by the running web server, reload/restart LuCI web service during a maintenance window."
