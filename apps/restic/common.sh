#!/usr/bin/env bash
# Current operations use the protected host installation, never env-file secrets.
set -euo pipefail
restic_operator() {
    local helper=/opt/kroacnet-backup/backup_cli.py
    [[ -f "$helper" ]] || { echo "Missing installed backup operator: $helper" >&2; return 1; }
    if (( EUID == 0 )); then
        /usr/bin/python3 -I "$helper" "$@"
    else
        sudo /usr/bin/python3 -I "$helper" "$@"
    fi
}
