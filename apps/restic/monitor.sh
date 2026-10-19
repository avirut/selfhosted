#!/usr/bin/env bash
# Inspect the shared snapshot catalogue; existing QM delivers state changes.
set -euo pipefail
umask 077
[[ $# == 1 ]] || { echo 'Usage: monitor.sh ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STATE=/var/lib/kroacnet-backup/shared-monitor
mkdir -p "$STATE"
exec 8>"$STATE/lock"; flock -n 8 || exit 0
catalogue=$STATE/snapshots.json
if ! "$SCRIPT_DIR/list-snapshots.sh" "$1" --json > "$catalogue.new"; then
    echo 'Shared backup repository is unavailable' >&2
    exit 1
fi
mv "$catalogue.new" "$catalogue"
now=$(date +%s)
for host in skepsis sophon-media sophon-gpu sophon ambrosia.local chrysaora; do
    profiles=(apps)
    if [[ $host == skepsis ]]; then profiles+=(embral); fi
    for profile in "${profiles[@]}"; do
        key=$host-$profile
        latest=$(jq -r --arg h "$host" --arg p "$profile" '[.[] | select(.hostname == $h and (.tags // [] | index($p)))] | max_by(.time) | .time // empty' "$catalogue")
        condition=healthy
        if [[ ! $latest ]] || (( now - $(date -d "$latest" +%s) > 108000 )); then condition=stale; fi
        previous=$(cat "$STATE/$key.state" 2>/dev/null || true)
        [[ $condition != "$previous" ]] || continue
        if [[ $previous || $condition != healthy ]]; then
            pending=$STATE/$key.pending.json
            if [[ ! -f $pending ]]; then
                text="Backups: $host/$profile is $condition."
                jq -n --arg requestKey "backups:$key:$now" --arg text "$text" '{requestKey:$requestKey,text:$text}' > "$pending"
            fi
            (cd /home/avirut/qm && runuser -u avirut -- /home/avirut/.local/bin/node scripts/owner-message.ts enqueue < "$pending") > /dev/null
            rm "$pending"
        fi
        printf '%s\n' "$condition" > "$STATE/$key.state"
    done
done
