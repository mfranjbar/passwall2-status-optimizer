#!/bin/sh
# Passwall2 Status Optimizer - restore the exact backup from the last successful install
set -eu
umask 077

STATUS_FILE='/usr/lib/lua/luci/view/passwall2/global/status.htm'
CONTROLLER_FILE='/usr/lib/lua/luci/controller/passwall2.lua'
BACKUP_ROOT='/root/backup/passwall2-status-optimizer'
ACTIVE_FILE="$BACKUP_ROOT/active-backup"
WORK="$BACKUP_ROOT/restore.$$"

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$(id -u)" = 0 ] || die 'Run as root.'
[ -s "$ACTIVE_FILE" ] || die 'No active installation backup record exists; refusing to guess.'
BACKUP="$(cat "$ACTIVE_FILE")"
case "$BACKUP" in "$BACKUP_ROOT"/*) ;; *) die 'Backup record points outside the optimizer backup directory.' ;; esac
[ -f "$BACKUP/status.htm.before" ] || die 'Original status.htm backup is missing.'
[ -f "$BACKUP/passwall2.lua.before" ] || die 'Original controller backup is missing.'
[ -f "$STATUS_FILE" ] && [ -f "$CONTROLLER_FILE" ] || die 'One or both Passwall2 target files are missing.'

mkdir -p "$WORK"
cp -p "$BACKUP/status.htm.before" "$WORK/status.htm"
cp -p "$BACKUP/passwall2.lua.before" "$WORK/passwall2.lua"
cmp -s "$BACKUP/status.htm.before" "$WORK/status.htm" || die 'Status restore staging verification failed.'
cmp -s "$BACKUP/passwall2.lua.before" "$WORK/passwall2.lua" || die 'Controller restore staging verification failed.'

# Preserve the current pair so a failed second replacement can be rolled back.
cp -p "$STATUS_FILE" "$WORK/status.current"
cp -p "$CONTROLLER_FILE" "$WORK/controller.current"
mv -f "$WORK/status.htm" "$STATUS_FILE" || die 'Could not restore status.htm.'
if ! mv -f "$WORK/passwall2.lua" "$CONTROLLER_FILE"; then
    cp -p "$WORK/status.current" "$STATUS_FILE"
    die 'Could not restore controller; status.htm was rolled back.'
fi
if ! cmp -s "$STATUS_FILE" "$BACKUP/status.htm.before" || ! cmp -s "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.before"; then
    cp -p "$WORK/status.current" "$STATUS_FILE"
    cp -p "$WORK/controller.current" "$CONTROLLER_FILE"
    die 'Restore verification failed; previous installed files were restored.'
fi

rm -f "$ACTIVE_FILE"
echo '[OK] Original status.htm and passwall2.lua restored.'
echo "[INFO] Backup retained: $BACKUP"
echo '[INFO] No services were restarted.'
