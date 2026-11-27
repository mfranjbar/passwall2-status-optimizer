#!/bin/sh
# Passwall2 Status Optimizer - backup, then the three requested edits only
set -eu
umask 077

STATUS_URL='https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm'
STATUS_FILE='/usr/lib/lua/luci/view/passwall2/global/status.htm'
CONTROLLER_FILE='/usr/lib/lua/luci/controller/passwall2.lua'
BACKUP_ROOT='/root/backup/passwall2-status-optimizer'
ACTIVE_FILE="$BACKUP_ROOT/active-backup"
BACKUP=''
CHANGED=0
ACTIVE_TMP=''

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

rollback() {
    [ "$CHANGED" -eq 1 ] || return 0
    printf '[WARN] Installation failed; restoring both original files.\n' >&2
    [ -n "$BACKUP" ] && [ -f "$BACKUP/status.htm.before" ] &&
        cp -p "$BACKUP/status.htm.before" "$STATUS_FILE"
    [ -n "$BACKUP" ] && [ -f "$BACKUP/passwall2.lua.before" ] &&
        cp -p "$BACKUP/passwall2.lua.before" "$CONTROLLER_FILE"
    CHANGED=0
}
cleanup() {
    rollback
    [ -z "$ACTIVE_TMP" ] || rm -f "$ACTIVE_TMP"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$(id -u)" = 0 ] || die 'Run as root.'
[ -f /etc/openwrt_release ] || die 'This installer is intended for OpenWrt/ImmortalWrt.'
for cmd in wget sed grep cp cmp mkdir date mv rm; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done
[ -f "$STATUS_FILE" ] || die "Passwall2 status page not found: $STATUS_FILE"
[ -f "$CONTROLLER_FILE" ] || die "Passwall2 controller not found: $CONTROLLER_FILE"

# Confirm the exact controller line exists once before touching either live file.
[ "$(grep -Ec 'local result = luci\.sys\.exec\(.*curl' "$CONTROLLER_FILE" || true)" -eq 1 ] ||
    die 'Expected exactly one local result curl assignment in passwall2.lua.'

# STEP 1: Back up both original files before any installation command.
mkdir -p "$BACKUP_ROOT"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/$STAMP"
N=0
while [ -e "$BACKUP" ]; do
    N=$((N + 1))
    BACKUP="$BACKUP_ROOT/$STAMP-$N"
done
mkdir -p "$BACKUP"
cp -p "$STATUS_FILE" "$BACKUP/status.htm.before"
cp -p "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.before"
cmp -s "$STATUS_FILE" "$BACKUP/status.htm.before" || die 'status.htm backup verification failed.'
cmp -s "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.before" || die 'controller backup verification failed.'
CHANGED=1
info "Verified backup created: $BACKUP"

# STEP 2: Download the requested upstream status.htm to its final location.
wget 'https://raw.githubusercontent.com/iranopenwrt/auto/refs/heads/main/resources/status.htm' -O /usr/lib/lua/luci/view/passwall2/global/status.htm ||
    die 'Could not download the requested status.htm; originals will be restored.'

# STEP 3: Apply the exact requested controller replacement.
sed -i 's@local result = luci.sys.exec.*@local result = luci.sys.exec(string.format("curl --connect-timeout 3 %s -o /dev/null -I -sk -w \\"%%{http_code}:%%{time_appconnect}\\" %s", (url:find("youtube.com") or url:find("x.com") or url:find("twitter.com")) and "--socks5-hostname 127.0.0.1:1070" or "", url))@' /usr/lib/lua/luci/controller/passwall2.lua ||
    die 'Controller sed operation failed; originals will be restored.'

# STEP 4: Apply the requested sequential status checks (3000 / 1000 / 1000 ms).
F='/usr/lib/lua/luci/view/passwall2/global/status.htm'
[ -f "$F" ] || die 'STATUS FILE NOT FOUND'

grep -qF "check_connect('arvan','https://www.arvancloud.ir/fa')" "$F" && {
    echo 'ALREADY INSTALLED - STOP'
    die 'The exact Arvan insertion already exists in the downloaded status file.'
}

grep -qF "check_connect('arvan', 'https://www.arvancloud.ir/fa')" "$F" || die 'Arvan source check missing.'
grep -qF "check_connect('youtube', 'https://www.youtube.com/')" "$F" || die 'YouTube source check missing.'
grep -qF "check_connect('twitter', 'https://x.com/')" "$F" || die 'X source check missing.'
grep -qF '//]]>' "$F" || die 'INSERT POINT NOT FOUND'

sed -i "/\/\/]]>/i\\
                setTimeout(function() {\\
                    check_connect('arvan','https://www.arvancloud.ir/fa');\\
                    setTimeout(function() {\\
                        check_connect('youtube','https://www.youtube.com/');\\
                        setTimeout(function() {\\
                            check_connect('twitter','https://x.com/');\\
                        }, 1000);\\
                    }, 1000);\\
                }, 3000);\\
" "$F" || die 'Could not insert the requested status block.'

grep -qF "check_connect('arvan','https://www.arvancloud.ir/fa')" "$F" || die 'Final status block verification failed.'
[ "$(grep -Fc '}, 1000);' "$F")" -eq 2 ] || die 'Expected exactly two 1000 ms timers.'
grep -qF '}, 3000);' "$F" || die 'Final 3000 ms timer verification failed.'
grep -qF 'url:find("youtube.com")' "$CONTROLLER_FILE" || die 'Controller YouTube route verification failed.'
grep -qF 'url:find("x.com")' "$CONTROLLER_FILE" || die 'Controller X route verification failed.'
grep -qF '127.0.0.1:1070' "$CONTROLLER_FILE" || die 'Controller SOCKS5 verification failed.'

# Record the exact backup used by this successful installation.
ACTIVE_TMP="$BACKUP_ROOT/active-backup.tmp.$$"
printf '%s\n' "$BACKUP" > "$ACTIVE_TMP"
mv -f "$ACTIVE_TMP" "$ACTIVE_FILE"
ACTIVE_TMP=''
CHANGED=0

echo '===== INSTALLED BLOCK ====='
grep -n -A 10 -B 2 "check_connect('arvan','https://www.arvancloud.ir/fa')" "$F"
ok 'Installation completed. Only the two requested Passwall2 files were changed.'
info "Original files are backed up in: $BACKUP"
info 'Timing: Arvan +3000 ms, YouTube +4000 ms, X +5000 ms (sequential).'
info 'No services, UCI settings, packages, DNS, firewall, or routing configuration were changed.'
