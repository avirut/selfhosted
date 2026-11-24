#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 1 ]] || { echo 'Usage: verify.sh ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/health.sh"
result=$BACKUP_STATE/verify-result
stage=lock subject=''
trap 'write_result "$result" failed "$stage" "$subject"' ERR
trap 'write_result "$result" failed "$stage" "$subject"; exit 143' TERM
exec 9>/var/lib/kroacnet-backup/operation.lock; flock -w 300 9
stage=config
set -a
source "$1"
set +a
work=$(mktemp -d /var/lib/kroacnet-backup/verify.XXXXXX)
trap 'rm -rf "$work"' EXIT
stage=catalogue
"$SCRIPT_DIR/list-snapshots.sh" "$1" --json > "$work/snapshots.json"
literal() { printf '%s\n' "$1" | sed -e 's/[][\\*?]/\\&/g'; }
for subject in "${BACKUP_SETS[@]}"; do
    host=${subject%/*} profile=${subject##*/}
    stage=missing
    id=$(jq -r --arg h "$host" --arg p "$profile" '[.[] | select(.hostname == $h and (.tags // [] | index($p)))] | max_by(.time) | .id // empty' "$work/snapshots.json")
    [[ $id ]]
    stage=inventory
    restic ls --json "$id" | jq -r 'select(.type == "file" and .size > 0 and .size < 2097152) | .path' > "$work/files"
    stage=sample
    { grep -E '/stage/(postgres|sqlite)/' "$work/files" | shuf -n 4 || true; shuf -n 8 "$work/files"; } | sort -u > "$work/selection"
    [[ -s $work/selection ]]
    args=()
    while IFS= read -r path; do args+=(--include "$(literal "$path")"); done < "$work/selection"
    target=$work/$host-$profile
    stage=restore
    "$SCRIPT_DIR/restore.sh" "$1" "$id" --target "$target" --verify "${args[@]}" > "$work/restore.log"
    stage=validate
    while IFS= read -r path; do
        file=$target$path
        [[ -f $file ]]
        case $path in
            */stage/sqlite/*) [[ $(sqlite3 -batch -bail -readonly "$file" 'PRAGMA integrity_check;') == ok ]];;
            */stage/postgres/*.dump) [[ $(head -c 5 "$file") == PGDMP ]];;
        esac
    done < "$work/selection"
    echo "Verified $subject $id"
done
stage=record subject=''
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/kroacnet-backup/restore-success
write_result "$result" success complete
