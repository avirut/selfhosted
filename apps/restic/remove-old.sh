#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if [[ ${1:-} == --help ]]; then
    echo 'Usage: remove-old.sh [selfhosted.env] [--apply]'
    echo 'Default previews current local retention. --apply runs the existing guarded maintenance job.'
    echo 'Never deletes legacy storage. Current retention applies to all local profiles.'
    exit 0
fi
if [[ ${1:-} == selfhosted.env ]]; then
    echo 'Using current local retention; the legacy env is not loaded.' >&2
    shift
fi
restic_operator retention "$@"
