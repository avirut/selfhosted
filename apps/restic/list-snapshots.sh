#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if [[ ${1:-} == --help ]]; then
    echo 'Usage: list-snapshots.sh [apps|embral|all|selfhosted.env] [--latest N] [--json]'
    echo '       list-snapshots.sh --legacy ENV_FILE (retired repository, read-only listing)'
    exit 0
fi
if [[ ${1:-} == --legacy ]]; then
    (( $# == 2 )) || { echo 'Specify exactly one trusted legacy env file' >&2; exit 2; }
    envfile=$2
    [[ $envfile == /* ]] || envfile="$(dirname -- "${BASH_SOURCE[0]}")/$envfile"
    echo 'LEGACY repository: not used by current backups. Sizes shown are logical snapshot sizes.' >&2
    set -a
    source "$envfile"
    set +a
    exec /usr/bin/restic -r "s3:${S3_ENDPOINT:?Missing S3_ENDPOINT}" snapshots
fi
args=()
case ${1:-} in
    selfhosted.env) echo 'selfhosted.env now selects current apps; use --legacy selfhosted.env for old snapshots.' >&2; args+=(--profile apps); shift;;
    apps|embral) args+=(--profile "$1"); shift;;
    all) args+=(--host all); shift;;
esac
restic_operator list "${args[@]}" "$@"
