#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: maintenance.sh ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec 9>/var/lib/kroacnet-backup/operation.lock
flock -w 300 9
# Do not prune if any required set lacks a current successful recovery point.
"$SCRIPT_DIR/list-snapshots.sh" "$1" --json > /var/lib/kroacnet-backup/snapshots.json
now=$(date +%s)
restored=$(cat /var/lib/kroacnet-backup/restore-success)
(( now - $(date -d "$restored" +%s) < 3456000 )) || { echo 'Restore verification is stale' >&2; exit 1; }
for host in skepsis sophon-media sophon-gpu sophon ambrosia.local chrysaora; do
    latest=$(jq -r --arg h "$host" '[.[] | select(.hostname == $h and (.tags // [] | index("apps")))] | max_by(.time) | .time // empty' /var/lib/kroacnet-backup/snapshots.json)
    [[ $latest ]] || { echo "No apps snapshot for $host" >&2; exit 1; }
    # The snapshot time includes nanoseconds and zone; jq normalizes UTC times.
    epoch=$(date -d "$latest" +%s)
    (( now - epoch < 108000 )) || { echo "Stale snapshot for $host" >&2; exit 1; }
done
latest=$(jq -r '[.[] | select(.hostname == "skepsis" and (.tags // [] | index("embral")))] | max_by(.time) | .time // empty' /var/lib/kroacnet-backup/snapshots.json)
[[ $latest ]] && (( now - $(date -d "$latest" +%s) < 108000 )) || { echo 'Stale Embral snapshot' >&2; exit 1; }
"$SCRIPT_DIR/remove-old.sh" "$1" --dry-run > /var/lib/kroacnet-backup/retention-preview.txt
# One shared repository: one integrity check and one prune.
set -a
# shellcheck disable=SC1090
source "$1"
set +a
restic --retry-lock 5m check --read-data-subset "$(( (10#$(date +%V) - 1) % 13 + 1 ))/13"
"$SCRIPT_DIR/remove-old.sh" "$1" --prune
restic --retry-lock 5m check
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/kroacnet-backup/maintenance-success
