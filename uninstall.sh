#!/bin/sh
# Passwall2 Status Optimizer - installation-bound, guarded two-file restore
set -eu
umask 077

STATUS_FILE='/usr/lib/lua/luci/view/passwall2/global/status.htm'
CONTROLLER_FILE='/usr/lib/lua/luci/controller/passwall2.lua'
BACKUP_ROOT='/root/backup/passwall2-status-optimizer'
ACTIVE_FILE="$BACKUP_ROOT/active-backup"
WORK="/tmp/passwall2-status-optimizer-uninstall.$$"
STATUS_STAGE="${STATUS_FILE}.pwso-restore.$$"
CONTROLLER_STAGE="${CONTROLLER_FILE}.pwso-restore.$$"
STATUS_MARKER='PWSO_AUTO_TEST_SEQUENCE_V1'
CONTROLLER_MARKER='PWSO_SOCKS_ROUTE_V1'

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
    rm -rf "$WORK"
    rm -f "$STATUS_STAGE" "$CONTROLLER_STAGE" "$STATUS_STAGE.rollback" "$CONTROLLER_STAGE.rollback"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$(id -u)" = 0 ] || die 'Run as root.'
[ -f "$STATUS_FILE" ] || die "Passwall2 status page not found: $STATUS_FILE"
[ -f "$CONTROLLER_FILE" ] || die "Passwall2 controller not found: $CONTROLLER_FILE"
grep -Fq "$STATUS_MARKER" "$STATUS_FILE" || die 'Optimizer marker not found in status.htm; refusing to restore unrelated files.'
grep -Fq "$CONTROLLER_MARKER" "$CONTROLLER_FILE" || die 'Optimizer marker not found in passwall2.lua; refusing to restore unrelated files.'
[ -s "$ACTIVE_FILE" ] || die 'No installation-specific backup record exists. Refusing to guess which backup belongs to this installation.'

BACKUP="$(cat "$ACTIVE_FILE")"
case "$BACKUP" in "$BACKUP_ROOT"/*) ;; *) die 'The active backup record points outside the expected backup directory.' ;; esac
[ -d "$BACKUP" ] || die "Recorded backup directory does not exist: $BACKUP"
for file in status.htm.before passwall2.lua.before status.htm.after passwall2.lua.after; do
    [ -f "$BACKUP/$file" ] || die "Recorded backup is incomplete ($file missing); no files changed."
done

# Refuse to overwrite any edits made after installation.
cmp -s "$STATUS_FILE" "$BACKUP/status.htm.after" || die 'status.htm has changed since installation. No files changed; inspect it before restoring.'
cmp -s "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.after" || die 'passwall2.lua has changed since installation. No files changed; inspect it before restoring.'

mkdir -p "$WORK"
cp -p "$BACKUP/status.htm.before" "$STATUS_STAGE"
cp -p "$BACKUP/passwall2.lua.before" "$CONTROLLER_STAGE"
cmp -s "$BACKUP/status.htm.before" "$STATUS_STAGE" || die 'Status restore staging verification failed.'
cmp -s "$BACKUP/passwall2.lua.before" "$CONTROLLER_STAGE" || die 'Controller restore staging verification failed.'
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

if ! cmp -s "$STATUS_FILE" "$BACKUP/status.htm.before" || ! cmp -s "$CONTROLLER_FILE" "$BACKUP/passwall2.lua.before"; then
    cp -p "$WORK/status.installed" "$STATUS_STAGE"
    cp -p "$WORK/controller.installed" "$CONTROLLER_STAGE"
    mv -f "$STATUS_STAGE" "$STATUS_FILE" || die 'Restore verification failed and status.htm rollback failed; manual recovery is required.'
    mv -f "$CONTROLLER_STAGE" "$CONTROLLER_FILE" || die 'Restore verification failed and controller rollback failed; manual recovery is required.'
    die 'Restore verification failed; the installed pair was restored.'
fi

rm -f "$ACTIVE_FILE"
ok 'Passwall2 Status Optimizer has been removed.'
info "Restored both original files from the exact installation backup: $BACKUP"
info 'No services were restarted. Refresh the Passwall2 LuCI page.'
info 'The backup directory was retained; it was not deleted.'
