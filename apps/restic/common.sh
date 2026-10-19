#!/usr/bin/env bash
# Only credentials loading; every entry point invokes restic directly.
set -euo pipefail
if [[ ${1:-} == --help || $# == 0 ]]; then
    echo "Usage: $(basename "$0") ENV_FILE [restic arguments...]"; exit 0
fi
RESTIC_ENV=$1
[[ -f $RESTIC_ENV ]] || { echo 'Environment file not found' >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$RESTIC_ENV"
set +a
: "${RESTIC_REPOSITORY:?Set RESTIC_REPOSITORY}" "${RESTIC_PASSWORD:?Set RESTIC_PASSWORD}"
shift
