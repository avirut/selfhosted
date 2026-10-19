#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'Usage: run-backup.sh ENV HOST_CONFIG PROFILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=$1; HOST_CONFIG=$2; PROFILE=$3
BASE=/var/lib/kroacnet-backup
# shellcheck disable=SC1090
source "$HOST_CONFIG"
mkdir -p "$BASE"
# Linux flock; macOS launchd does not run concurrent instances of the same job.
if command -v flock >/dev/null; then
    exec 9>"$BASE/operation.lock"
    flock -w 300 9
fi
trap 'printf "%s\n" "failed $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BASE/$PROFILE/result"' ERR
"$SCRIPT_DIR/prepare.sh" "$HOST_CONFIG" "$PROFILE"
"$SCRIPT_DIR/backup.sh" "$ENV_FILE" "$BASE/$PROFILE/payload" --host "$BACKUP_HOST" --tag "$PROFILE" --one-file-system --json > "$BASE/$PROFILE/backup.jsonl"
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BASE/$PROFILE/last-success"
printf '%s\n' success > "$BASE/$PROFILE/result"
rm -rf "$BASE/$PROFILE/previous"
