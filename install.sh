#!/bin/sh
# Passwall2 Status Optimizer - guarded, reversible two-file patch
set -eu
umask 077

STATUS_URL='https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm'
STATUS_FILE='/usr/lib/lua/luci/view/passwall2/global/status.htm'
CONTROLLER_FILE='/usr/lib/lua/luci/controller/passwall2.lua'
BACKUP_ROOT='/root/backup/passwall2-status-optimizer'
ACTIVE_FILE='/root/backup/passwall2-status-optimizer/active-backup'
WORK="/tmp/passwall2-status-optimizer.$$"
STATUS_MARKER='PWSO_AUTO_TEST_SEQUENCE_V1'
CONTROLLER_MARKER='PWSO_SOCKS_ROUTE_V1'
STATUS_STAGE="${STATUS_FILE}.pwso.$$"
CONTROLLER_STAGE="${CONTROLLER_FILE}.pwso.$$"
BACKUP=''
CHANGED=0

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

cleanup() {
    [ "$CHANGED" -eq 0 ] || rollback
    rm -rf "$WORK"
    rm -f "$STATUS_STAGE" "$CONTROLLER_STAGE" "$STATUS_STAGE.restore" "$CONTROLLER_STAGE.restore"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

rollback() {
    [ "$CHANGED" -eq 1 ] || return 0
    warn 'Installation did not complete; restoring the original files.'
    if [ -n "$BACKUP" ] && [ -f "$BACKUP/status.htm.before" ]; then
        cp -p "$BACKUP/status.htm.before" "$STATUS_STAGE.restore" && mv -f "$STATUS_STAGE.restore" "$STATUS_FILE" || warn 'Automatic status.htm rollback failed.'
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP/passwall2.lua.before" ]; then
        cp -p "$BACKUP/passwall2.lua.before" "$CONTROLLER_STAGE.restore" && mv -f "$CONTROLLER_STAGE.restore" "$CONTROLLER_FILE" || warn 'Automatic passwall2.lua rollback failed.'
    fi
    CHANGED=0
}

[ "$(id -u)" = 0 ] || die 'Run as root.'
[ -f /etc/openwrt_release ] || die 'This installer is intended for OpenWrt.'
for cmd in wget awk grep cmp cp mv mkdir date rm cat; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done
[ -f "$STATUS_FILE" ] || die "Passwall2 status page not found: $STATUS_FILE"
[ -f "$CONTROLLER_FILE" ] || die "Passwall2 controller not found: $CONTROLLER_FILE"

# Detect a complete installation without trusting marker strings alone.
status_marked=0
controller_marked=0
grep -Fq "$STATUS_MARKER" "$STATUS_FILE" && status_marked=1 || true
grep -Fq "$CONTROLLER_MARKER" "$CONTROLLER_FILE" && controller_marked=1 || true
if [ "$status_marked" -eq 1 ] && [ "$controller_marked" -eq 1 ]; then
    grep -Fq "check_connect('arvan', 'https://www.arvancloud.ir/fa')" "$STATUS_FILE" || die 'Installed status page is inconsistent; no files changed.'
    grep -Fq "check_connect('youtube', 'https://www.youtube.com/')" "$STATUS_FILE" || die 'Installed status page is inconsistent; no files changed.'
    grep -Fq "check_connect('twitter', 'https://x.com/')" "$STATUS_FILE" || die 'Installed status page is inconsistent; no files changed.'
    [ "$(grep -Fc 'setTimeout(function() {' "$STATUS_FILE")" -eq 3 ] || die 'Installed timing sequence is inconsistent; no files changed.'
    [ "$(grep -Fc '}, 1000);' "$STATUS_FILE")" -eq 2 ] || die 'Installed timing delays are inconsistent; no files changed.'
    grep -Fq '}, 3000);' "$STATUS_FILE" || die 'Installed Arvan delay is inconsistent; no files changed.'
    grep -Fq -- '--socks5-hostname 127.0.0.1:1070' "$CONTROLLER_FILE" || die 'Installed controller is inconsistent; no files changed.'
    grep -Fq 'url:match("^https?://www%.youtube%.com/")' "$CONTROLLER_FILE" || die 'Installed YouTube route is inconsistent; no files changed.'
    grep -Fq 'url:match("^https?://x%.com/")' "$CONTROLLER_FILE" || die 'Installed X route is inconsistent; no files changed.'
    grep -Fq 'util.shellquote(url or "")' "$CONTROLLER_FILE" || die 'Installed URL quoting is inconsistent; no files changed.'
    [ -s "$ACTIVE_FILE" ] || die 'A legacy installation is present without an installation-specific backup record. No files changed; restore it manually from the correct backup.'
    ACTIVE_BACKUP="$(cat "$ACTIVE_FILE")"
    case "$ACTIVE_BACKUP" in "$BACKUP_ROOT"/*) ;; *) die 'The active backup record points outside the backup directory; refusing to continue.' ;; esac
    [ -f "$ACTIVE_BACKUP/status.htm.before" ] && [ -f "$ACTIVE_BACKUP/passwall2.lua.before" ] || die 'The active backup record is incomplete; no files changed.'
    ok 'Optimizer is already installed and its recorded backup is present; no files changed.'
    exit 0
fi
[ "$status_marked" -eq 0 ] && [ "$controller_marked" -eq 0 ] || die 'Partial installation detected. No files changed; restore both files from the same backup.'

mkdir -p "$WORK"
info 'Downloading the requested status.htm base...'
wget -q -O "$WORK/status.base" "$STATUS_URL" || die 'Could not download the status.htm source.'
[ -s "$WORK/status.base" ] || die 'Downloaded status.htm is empty.'
grep -Fq 'function check_connect(type, url)' "$WORK/status.base" || die 'Unexpected status.htm source structure.'
grep -Fq "check_connect('arvan', 'https://www.arvancloud.ir/fa')" "$WORK/status.base" || die 'Arvan test entry is missing.'
grep -Fq "check_connect('youtube', 'https://www.youtube.com/')" "$WORK/status.base" || die 'YouTube test entry is missing.'
grep -Fq "check_connect('twitter', 'https://x.com/')" "$WORK/status.base" || die 'X test entry is missing.'
[ "$(grep -Fxc '//]]>' "$WORK/status.base" || true)" -eq 1 ] || die 'Expected exactly one JavaScript closing marker.'
! grep -Fq "$STATUS_MARKER" "$WORK/status.base" || die 'Source already contains the optimizer marker.'

# Validate the controller narrowly: one single-line curl assignment inside connect_status().
grep -Fq 'local util = require "luci.util"' "$CONTROLLER_FILE" || die 'Controller lacks luci.util; refusing an unsafe patch.'
[ "$(grep -Fc 'function connect_status()' "$CONTROLLER_FILE" || true)" -eq 1 ] || die 'Expected exactly one connect_status() function.'
sed -n '/^function connect_status()/,/^function /p' "$CONTROLLER_FILE" > "$WORK/connect_status.source"
[ "$(grep -Ec 'local result = luci\.sys\.exec\(.*curl.*url' "$WORK/connect_status.source" || true)" -eq 1 ] || die 'Expected exactly one supported single-line curl assignment inside connect_status(); no files changed.'
USER_AGENT=''
grep -Fq -- '-A "Mozilla/5.0"' "$WORK/connect_status.source" && USER_AGENT=' -A "Mozilla/5.0"' || true

cat > "$WORK/status.fragment" <<'FRAGMENT'
		/* PWSO_AUTO_TEST_SEQUENCE_V1 */
		// Arvan starts at +3000 ms; YouTube +1000 ms; X +1000 ms.
		setTimeout(function() {
			check_connect('arvan', 'https://www.arvancloud.ir/fa');
			setTimeout(function() {
				check_connect('youtube', 'https://www.youtube.com/');
				setTimeout(function() {
					check_connect('twitter', 'https://x.com/');
				}, 1000);
			}, 1000);
		}, 3000);
FRAGMENT

cat > "$WORK/controller.fragment" <<FRAGMENT
    -- PWSO_SOCKS_ROUTE_V1
    local proxy_args = ""
    if url and (url:match("^https?://www%.youtube%.com/") or url:match("^https?://x%.com/")) then
        proxy_args = " --socks5-hostname 127.0.0.1:1070"
    end
    local result = luci.sys.exec("curl" .. proxy_args .. " --connect-timeout 3 -o /dev/null -I -sk${USER_AGENT} -w '%{http_code}:%{time_appconnect}' " .. util.shellquote(url or ""))
FRAGMENT

awk -v fragment="$WORK/status.fragment" '
$0 == "//]]>" {
    count++
    while ((getline line < fragment) > 0) print line
    close(fragment)
}
{ print }
END { if (count != 1) exit 41 }
' "$WORK/status.base" > "$WORK/status.new" || die 'Could not safely patch status.htm.'

awk -v fragment="$WORK/controller.fragment" '
/^function connect_status\(\)/ { in_connect=1; starts++ }
/^function / && !/^function connect_status\(\)/ && in_connect { in_connect=0 }
in_connect && /local result = luci\.sys\.exec\(/ && /curl/ && /url/ {
    count++
    while ((getline line < fragment) > 0) print line
    close(fragment)
    next
}
{ print }
END { if (starts != 1 || count != 1) exit 42 }
' "$CONTROLLER_FILE" > "$WORK/controller.new" || die 'Could not safely patch the controller.'

# Validate the exact sequence and the two narrowly-scoped proxy routes.
grep -Fq "$STATUS_MARKER" "$WORK/status.new" || die 'Status marker validation failed.'
[ "$(grep -Fc 'setTimeout(function() {' "$WORK/status.new")" -eq 3 ] || die 'Expected exactly three nested timers.'
grep -Fq "}, 3000);" "$WORK/status.new" || die 'Arvan timer validation failed.'
grep -Fq "check_connect('arvan', 'https://www.arvancloud.ir/fa');" "$WORK/status.new" || die 'Arvan call validation failed.'
grep -Fq "check_connect('youtube', 'https://www.youtube.com/');" "$WORK/status.new" || die 'YouTube call validation failed.'
grep -Fq "check_connect('twitter', 'https://x.com/');" "$WORK/status.new" || die 'X call validation failed.'
grep -Fq "$CONTROLLER_MARKER" "$WORK/controller.new" || die 'Controller marker validation failed.'
grep -Fq -- '--socks5-hostname 127.0.0.1:1070' "$WORK/controller.new" || die 'SOCKS5 route validation failed.'
grep -Fq 'url:match("^https?://www%.youtube%.com/")' "$WORK/controller.new" || die 'YouTube host guard validation failed.'
grep -Fq 'url:match("^https?://x%.com/")' "$WORK/controller.new" || die 'X host guard validation failed.'
grep -Fq 'util.shellquote(url or "")' "$WORK/controller.new" || die 'URL shell-quoting validation failed.'
if command -v luac >/dev/null 2>&1; then
    luac -p "$WORK/controller.new" || die 'Lua syntax validation failed.'
else
    warn 'luac is not installed; no package installation will be attempted.'
fi

# Prepare same-directory staging copies, retaining original owner and mode.
cp -p "$STATUS_FILE" "$STATUS_STAGE"
cat "$WORK/status.new" > "$STATUS_STAGE"
cp -p "$CONTROLLER_FILE" "$CONTROLLER_STAGE"
cat "$WORK/controller.new" > "$CONTROLLER_STAGE"
cmp -s "$WORK/status.new" "$STATUS_STAGE" || die 'Staged status.htm verification failed.'
cmp -s "$WORK/controller.new" "$CONTROLLER_STAGE" || die 'Staged controller verification failed.'

# Create a unique backup only after every source and patch check has passed.
stamp="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/$stamp"
n=0
while [ -e "$BACKUP" ]; do
    n=$((n + 1))
    BACKUP="$BACKUP_ROOT/$stamp-$n"
done
mkdir -p "$BACKUP"
cp -p "$STATUS_FILE" "$BACKUP/status.htm.before"
cp -p "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.before"
cmp -s "$STATUS_FILE" "$BACKUP/status.htm.before" || die 'Status backup verification failed.'
cmp -s "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.before" || die 'Controller backup verification failed.'

# Atomic replacements from same-filesystem staging paths; rollback on any error.
CHANGED=1
if ! mv -f "$STATUS_STAGE" "$STATUS_FILE"; then
    die 'Could not replace status.htm; originals remain unchanged.'
fi
if ! mv -f "$CONTROLLER_STAGE" "$CONTROLLER_FILE"; then
    rollback
    die 'Could not replace passwall2.lua; rollback was attempted.'
fi
if ! cmp -s "$WORK/status.new" "$STATUS_FILE" || ! cmp -s "$WORK/controller.new" "$CONTROLLER_FILE"; then
    rollback
    die 'Post-install verification failed; rollback was attempted.'
fi

# Bind this installation to its exact backup and exact installed file pair.
cp -p "$STATUS_FILE" "$BACKUP/status.htm.after"
cp -p "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.after"
cmp -s "$STATUS_FILE" "$BACKUP/status.htm.after" || { rollback; die 'Could not verify installed status snapshot; rollback was attempted.'; }
cmp -s "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.after" || { rollback; die 'Could not verify installed controller snapshot; rollback was attempted.'; }
ACTIVE_TMP="$BACKUP_ROOT/active-backup.tmp.$"
printf '%s\\n' "$BACKUP" > "$ACTIVE_TMP"
if ! mv -f "$ACTIVE_TMP" "$ACTIVE_FILE"; then
    rm -f "$ACTIVE_TMP"
    rollback
    die 'Could not record the installation-specific backup; rollback was attempted.'
fi
CHANGED=0

ok 'Passwall2 Status Optimizer installed successfully.'
info "Backup: $BACKUP"
info 'Timing: Arvan +3000 ms, YouTube +4000 ms, X +5000 ms.'
info 'Routing: only YouTube and X checks use 127.0.0.1:1070; Arvan remains direct.'
info 'Only status.htm and passwall2.lua were changed.'
info 'No UCI settings, packages, feeds, DNS, firewall, routing, or services were changed.'
info 'Refresh the Passwall2 LuCI status page to load the updated view.'
