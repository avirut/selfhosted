#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'Usage: run-backup.sh ENV HOST_CONFIG PROFILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=$1; HOST_CONFIG=$2; PROFILE=$3
[[ $PROFILE == apps || $PROFILE == embral ]] || exit 2
BASE=/var/lib/kroacnet-backup
source "$HOST_CONFIG"
mkdir -p "$BASE/$PROFILE"
stage=lock
save_failure() {
    printf 'failed %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stage" > "$BASE/$PROFILE/result.new"
    mv "$BASE/$PROFILE/result.new" "$BASE/$PROFILE/result"
}
trap 'save_failure' ERR
if command -v flock >/dev/null; then
    exec 9>"$BASE/operation.lock"
    flock -w 300 9
fi
stage=prepare
errors=$BASE/$PROFILE/prepare.stderr
if "$SCRIPT_DIR/prepare.sh" "$HOST_CONFIG" "$PROFILE" 2> "$errors"; then
    cat "$errors" >&2
else
    status=$?
    case $(tail -n 1 "$errors") in
        'Required source unavailable:'*) stage=source;;
        'Room database mount changed'|'Source filesystem changed'|'Source dataset changed'|'Source is not on the root filesystem') stage=mount;;
        'SQLite online backup failed'|'SQLite integrity check failed') stage=sqlite;;
        'Conversation changed while copying'|'Invalid conversation JSONL') stage=conversation;;
        'No backup data prepared') stage=empty;;
    esac
    cat "$errors" >&2
    save_failure
    exit "$status"
fi
stage=upload
"$SCRIPT_DIR/backup.sh" "$ENV_FILE" "$BASE/$PROFILE/payload" --host "$BACKUP_HOST" --tag "$PROFILE" --one-file-system --json > "$BASE/$PROFILE/backup.jsonl"
stage=record
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BASE/$PROFILE/last-success"
rm -rf "$BASE/$PROFILE/previous"
printf '%s\n' success > "$BASE/$PROFILE/result.new"
mv "$BASE/$PROFILE/result.new" "$BASE/$PROFILE/result"
