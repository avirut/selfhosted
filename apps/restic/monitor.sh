#!/usr/bin/env bash
# Shared snapshot freshness, with stable queued alerts through the existing QM outbox.
set -euo pipefail
umask 077
[[ $# == 1 ]] || { echo 'Usage: monitor.sh ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STATE=/var/lib/kroacnet-backup/shared-monitor
mkdir -p "$STATE"
exec 8>"$STATE/lock"; flock -n 8 || exit 0
now=$(date +%s)
report() {
    local key=$1 condition=$2 previous sent pending=$STATE/$1.pending.json
    if [[ -f $pending ]]; then
        (cd /home/avirut/qm; jq '.request' "$pending" | runuser -u avirut -- /home/avirut/.local/bin/node scripts/owner-message.ts enqueue) >/dev/null
        printf '%s %s\n' "$(jq -r .condition "$pending")" "$now" > "$STATE/$key.state"
        rm "$pending"
    fi
    previous=; sent=0
    if [[ -f $STATE/$key.state ]]; then read -r previous sent < "$STATE/$key.state"; fi
    if [[ $condition == "$previous" ]] && { [[ $condition == healthy ]] || (( now - sent < 86400 )); }; then return; fi
    if [[ $previous || $condition != healthy ]]; then
        jq -n --arg requestKey "backups:$key:$now" --arg text "Backups: $key is $condition." --arg condition "$condition" '{condition:$condition,request:{requestKey:$requestKey,text:$text}}' > "$pending"
        (cd /home/avirut/qm; jq '.request' "$pending" | runuser -u avirut -- /home/avirut/.local/bin/node scripts/owner-message.ts enqueue) >/dev/null
        rm "$pending"
    fi
    printf '%s %s\n' "$condition" "$now" > "$STATE/$key.state"
}
catalogue=$STATE/snapshots.json
if ! "$SCRIPT_DIR/list-snapshots.sh" "$1" --json > "$catalogue.new"; then
    report repository unavailable
    exit 1
fi
report repository healthy
mv "$catalogue.new" "$catalogue"
for host in skepsis sophon-media sophon-gpu sophon ambrosia.local chrysaora; do
    profiles=(apps)
    if [[ $host == skepsis ]]; then profiles+=(embral); fi
    for profile in "${profiles[@]}"; do
        latest=$(jq -r --arg h "$host" --arg p "$profile" '[.[] | select(.hostname == $h and (.tags // [] | index($p)))] | max_by(.time) | .time // empty' "$catalogue")
        condition=healthy
        if [[ ! $latest ]] || (( now - $(date -d "$latest" +%s) > 108000 )); then condition=stale; fi
        if [[ $host == skepsis && -f /var/lib/kroacnet-backup/$profile/result ]] && grep -q '^failed ' "/var/lib/kroacnet-backup/$profile/result"; then condition=failed; fi
        report "$host-$profile" "$condition"
    done
done
for unit in maintenance verify; do
    condition=healthy
    if systemctl is-failed --quiet "restic-$unit.service"; then condition=failed; fi
    report "$unit" "$condition"
done
for entry in restore:3456000 maintenance:777600; do
    name=${entry%:*}; limit=${entry#*:}
    last=$(cat "/var/lib/kroacnet-backup/$name-success" 2>/dev/null || true)
    condition=healthy
    if [[ ! $last ]] || (( now - $(date -d "$last" +%s) > limit )); then condition=stale; fi
    report "$name-age" "$condition"
done
