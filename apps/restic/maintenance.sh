#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# == 1 ]] || { echo 'Usage: maintenance.sh ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/health.sh"
export TZ=America/Chicago
now=$(date +%s)
weekday=$(date -d "@$now" +%w)
today=$(date -d "@$now" +%F)
sunday=$(date -d "$today -$weekday days" +%F)
due=$(date -d "$sunday 05:30" +%s)
if (( now < due )); then
    due=$(date -d "$(date -d "$sunday -7 days" +%F) 05:30" +%s)
fi
completed=$(read_epoch "$BACKUP_STATE/maintenance-success" || echo 0)
(( completed < due )) || exit 0

result=$BACKUP_STATE/maintenance-result
stage=lock
failed() {
    local status=$1
    trap - ERR TERM INT
    write_result "$result" failed "$stage"
    echo "Maintenance failed during $stage (exit $status)." >&2
    exit "$status"
}
defer() {
    write_result "$result" deferred "$1" "${2:-}"
    echo "Maintenance deferred: $*"
    exit 0
}
step() {
    stage=$1
    write_result "$result" running "$stage"
}
trap 'failed "$?"' ERR
trap 'failed 143' TERM
trap 'failed 130' INT
exec 9>"$BACKUP_STATE/operation.lock"
flock -w 300 9 || defer lock
completed=$(read_epoch "$BACKUP_STATE/maintenance-success" || echo 0)
(( completed < due )) || exit 0

step catalogue
catalogue=$BACKUP_STATE/snapshots.json
if "$SCRIPT_DIR/list-snapshots.sh" "$1" --json > "$catalogue"; then
    jq -e 'type == "array"' "$catalogue" >/dev/null || { stage='catalogue-invalid'; failed 1; }
else
    status=$?
    stage=catalogue-$status
    failed "$status"
fi
now=$(date +%s)
restored=$(read_epoch "$BACKUP_STATE/restore-success") || defer restore-missing
(( now - restored < RESTORE_MAX_AGE )) || defer restore-stale
for set in "${BACKUP_SETS[@]}"; do
    condition=$(snapshot_status "$catalogue" "$set" "$now")
    [[ $condition == healthy ]] || defer "snapshot-$condition" "$set"
done

step retention
"$SCRIPT_DIR/remove-old.sh" "$1" --dry-run > "$BACKUP_STATE/retention-preview.txt"
step config
set -a
source "$1"
set +a
step precheck
restic --retry-lock 5m check --read-data-subset "$(( (10#$(date +%V) - 1) % 13 + 1 ))/13"
step prune
"$SCRIPT_DIR/remove-old.sh" "$1" --prune
step postcheck
restic --retry-lock 5m check
step record
date -u +%Y-%m-%dT%H:%M:%SZ > "$BACKUP_STATE/maintenance-success.new"
mv -- "$BACKUP_STATE/maintenance-success.new" "$BACKUP_STATE/maintenance-success"
write_result "$result" success complete
