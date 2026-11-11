#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --help || $# == 0 ]]; then
    echo "Usage: $(basename "$0") ENV_FILE [restic arguments...]"; exit 0
fi
RESTIC_ENV=$1
[[ -f $RESTIC_ENV ]] || { echo 'Environment file not found' >&2; exit 1; }
set -a
source "$RESTIC_ENV"
set +a
: "${RESTIC_REPOSITORY:?Set RESTIC_REPOSITORY}" "${RESTIC_PASSWORD:?Set RESTIC_PASSWORD}"
shift
