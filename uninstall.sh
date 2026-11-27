#!/bin/sh
# Passwall2 Status Optimizer - safe two-file restore
set -eu
umask 077

STATUS_FILE='/usr/lib/lua/luci/view/passwall2/global/status.htm'
CONTROLLER_FILE='/usr/lib/lua/luci/controller/passwall2.lua'
BACKUP_ROOT='/root/backup/passwall2-status-optimizer'
WORK="/tmp/passwall2-status-optimizer-uninstall.$$"
STATUS_STAGE="${STATUS_FILE}.pwso-restore.$$"
CONTROLLER_STAGE="${CONTROLLER_FILE}.pwso-restore.$$"
STATUS_MARKER='PWSO_AUTO_TEST_SEQUENCE_V1'
CONTROLLER_MARKER='PWSO_SOCKS_ROUTE_V1'
RESTORING=0

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
    rm -rf "$WORK"
    rm -f "$STATUS_STAGE" "$CONTROLLER_STAGE"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$(id -u)" = 0 ] || die 'Run as root.'
[ -f "$STATUS_FILE" ] || die "Passwall2 status page not found: $STATUS_FILE"
[ -f "$CONTROLLER_FILE" ] || die "Passwall2 controller not found: $CONTROLLER_FILE"

grep -Fq "$STATUS_MARKER" "$STATUS_FILE" || die 'Optimizer marker not found in status.htm; refusing to restore unrelated files.'
grep -Fq "$CONTROLLER_MARKER" "$CONTROLLER_FILE" || die 'Optimizer marker not found in passwall2.lua; refusing to restore unrelated files.'

[ -d "$BACKUP_ROOT" ] || die "Backup directory not found: $BACKUP_ROOT"

# Select the newest complete backup containing both original files.
BACKUP=''
for candidate in "$BACKUP_ROOT"/*; do
    [ -d "$candidate" ] || continue
    if [ -f "$candidate/status.htm.before" ] && [ -f "$candidate/passwall2.lua.before" ]; then
        BACKUP="$candidate"
    fi
done
[ -n "$BACKUP" ] || die 'No complete two-file backup was found; no files changed.'

mkdir -p "$WORK"
cp -p "$BACKUP/status.htm.before" "$STATUS_STAGE"
cp -p "$BACKUP/passwall2.lua.before" "$CONTROLLER_STAGE"
cmp -s "$BACKUP/status.htm.before" "$STATUS_STAGE" || die 'Status restore staging verification failed.'
cmp -s "$BACKUP/passwall2.lua.before" "$CONTROLLER_STAGE" || die 'Controller restore staging verification failed.'

# Keep a temporary copy of the installed pair so a failed second move can be rolled back.
cp -p "$STATUS_FILE" "$WORK/status.installed"
cp -p "$CONTROLLER_FILE" "$WORK/controller.installed"

if ! mv -f "$STATUS_STAGE" "$STATUS_FILE"; then
    die 'Could not restore status.htm; installed files remain unchanged.'
fi
if ! mv -f "$CONTROLLER_STAGE" "$CONTROLLER_FILE"; then
    cp -p "$WORK/status.installed" "$STATUS_STAGE"
    mv -f "$STATUS_STAGE" "$STATUS_FILE" || die 'Controller restore failed and status.htm rollback also failed; manual recovery is required.'
    die 'Could not restore passwall2.lua; status.htm was rolled back.'
fi

if grep -Fq "$STATUS_MARKER" "$STATUS_FILE" || grep -Fq "$CONTROLLER_MARKER" "$CONTROLLER_FILE"; then
    cp -p "$WORK/status.installed" "$STATUS_STAGE"
    cp -p "$WORK/controller.installed" "$CONTROLLER_STAGE"
    mv -f "$STATUS_STAGE" "$STATUS_FILE" || true
    mv -f "$CONTROLLER_STAGE" "$CONTROLLER_FILE" || true
    die 'Post-restore validation failed; attempted to restore the installed pair.'
fi

ok 'Passwall2 Status Optimizer has been removed.'
info "Restored both original files from: $BACKUP"
info 'No services were restarted. Refresh the Passwall2 LuCI page.'
info 'The backup directory was retained; it was not deleted.'
