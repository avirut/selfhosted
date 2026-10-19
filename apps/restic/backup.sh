#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if [[ ${1:-} == --help ]]; then
    echo 'Usage: backup.sh [apps|embral|selfhosted.env] (default: apps)'; exit 0
fi
(( $# <= 1 )) || { echo 'Expected one profile at most' >&2; exit 2; }
profile=${1:-apps}
if [[ $profile == selfhosted.env ]]; then
    echo 'selfhosted.env is a compatibility alias for current apps; the old env is not loaded.' >&2
    profile=apps
fi
restic_operator backup "$profile"
