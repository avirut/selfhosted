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
for host in skepsis sophon-media sophon-gpu sophon sophon-agent ambrosia.local chrysaora; do
    profiles=(apps)
    if [[ $host == skepsis ]]; then profiles+=(embral); fi
    for profile in "${profiles[@]}"; do
        subject=$host/$profile stage=missing
        id=$(jq -r --arg h "$host" --arg p "$profile" '[.[] | select(.hostname == $h and (.tags // [] | index($p)))] | max_by(.time) | .id // empty' "$work/snapshots.json")
        [[ $id ]]
        root=/var/lib/kroacnet-backup/$profile/payload
        case $host in
            ambrosia.local) root=/Users/avirut/Documents/Projects/kroacnet/private/backups/restic/stage/apps/payload;;
            chrysaora) root=/payload;;
        esac
        directories=("$root")
        case $host/$profile in
            skepsis/apps) directories+=("$root/files/home/avirut/.codex" "$root/files/home/avirut/.paseo");;
            sophon/apps) directories+=("$root/files/var/lib/pve-cluster" "$root/files/home/avirut/.paseo");;
            sophon-media/apps) directories+=("$root/files/home/avirut/.config/okearak/access");;
            sophon-gpu/apps) directories+=("$root/files/home/avirut/.config/sunshine");;
            sophon-agent/apps) directories+=("$root/files/home/avirut/.hermes");;
            ambrosia.local/apps) directories+=("$root/files/Users/avirut/.codex" "$root/files/Users/avirut/.paseo");;
            chrysaora/apps) directories+=("$root/codex");;
        esac
        stage=inventory
        restic ls --json "$id" "${directories[@]}" > "$work/files.jsonl"
        jq -rs '[.[] | select(.type == "file" and .size > 0 and .size < 2097152 and (.path | contains("/worktree/") | not))] | ([.[] | select(.path | test("/(state_5\\.sqlite|access\\.db|config\\.db)$"))][0:1] + [.[] | select(.path | test("/\\.paseo/config\\.json$|/sunshine/apps\\.json$|/\\.hermes/config\\.yaml$|^/payload/manifest\\.json$"))][0:1] + [.[] | select(.path | endswith("/prepared-at"))][0:1]) | .[].path' "$work/files.jsonl" > "$work/selection"
        stage=sample
        [[ -s $work/selection ]]
        args=()
        while IFS= read -r path; do args+=(--include "$path"); done < "$work/selection"
        target=$work/$host-$profile
        stage=restore
        "$SCRIPT_DIR/restore.sh" "$1" "$id" --target "$target" --verify "${args[@]}" > "$work/restore.log"
        stage=validate
        while IFS= read -r path; do
            file=$target$path
            [[ -f $file ]]
            case $file in
                *.db|*.sqlite) [[ $(sqlite3 -batch -bail -readonly "$file" 'PRAGMA integrity_check;') == ok ]];;
                *.json) jq empty "$file";;
            esac
        done < "$work/selection"
        echo "Verified $host/$profile $id"
    done
done
stage=record subject=''
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/kroacnet-backup/restore-success
write_result "$result" success complete
