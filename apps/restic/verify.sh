#!/usr/bin/env bash
# Restore small samples from every current host/set; use normal tools to read them.
set -euo pipefail
umask 077
[[ $# == 1 ]] || { echo 'Usage: verify.sh ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec 9>/var/lib/kroacnet-backup/operation.lock; flock -w 300 9
set -a
# shellcheck disable=SC1090
source "$1"
set +a
work=$(mktemp -d /var/lib/kroacnet-backup/verify.XXXXXX)
trap 'rm -rf "$work"' EXIT
"$SCRIPT_DIR/list-snapshots.sh" "$1" --json > "$work/snapshots.json"
for host in skepsis sophon-media sophon-gpu sophon ambrosia.local chrysaora; do
    profiles=(apps)
    if [[ $host == skepsis ]]; then profiles+=(embral); fi
    for profile in "${profiles[@]}"; do
        id=$(jq -r --arg h "$host" --arg p "$profile" '[.[] | select(.hostname == $h and (.tags // [] | index($p)))] | max_by(.time) | .id // empty' "$work/snapshots.json")
        [[ $id ]] || { echo "Missing $host/$profile" >&2; exit 1; }
        restic ls --json "$id" > "$work/files.jsonl"
        # Use known runtime stores, not authored test fixtures or JSON-with-comments.
        # Each Linux/Mac set also has prepared-at; Windows has its root manifest.
        jq -rs '[.[] | select(.type == "file" and .size > 0 and .size < 2097152 and (.path | contains("/worktree/") | not))] | ([.[] | select(.path | test("/(state_5\\.sqlite|access\\.db|config\\.db)$"))][0:1] + [.[] | select(.path | test("/\\.paseo/config\\.json$|/sunshine/apps\\.json$|^/payload/manifest\\.json$"))][0:1] + [.[] | select(.path | endswith("/prepared-at"))][0:1]) | .[].path' "$work/files.jsonl" > "$work/selection"
        [[ -s $work/selection ]] || { echo 'No verification sample found' >&2; exit 1; }
        args=()
        while IFS= read -r path; do args+=(--include "$path"); done < "$work/selection"
        target=$work/$host-$profile
        "$SCRIPT_DIR/restore.sh" "$1" "$id" --target "$target" --verify "${args[@]}" > "$work/restore.log"
        while IFS= read -r path; do
            file=$target$path
            [[ -f $file ]] || exit 1
            case $file in
                *.db|*.sqlite) [[ $(sqlite3 -batch -bail -readonly "$file" 'PRAGMA integrity_check;') == ok ]];;
                *.json) jq empty "$file";;
            esac
        done < "$work/selection"
        echo "Verified $host/$profile $id"
    done
done
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/kroacnet-backup/restore-success
