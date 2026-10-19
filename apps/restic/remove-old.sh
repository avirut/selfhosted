#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# Grouping protects every host and set; callers can preview with --dry-run.
exec restic --retry-lock 5m forget --group-by host,tags \
    --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --keep-yearly 3 "$@"
