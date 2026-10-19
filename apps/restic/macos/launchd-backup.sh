#!/bin/bash
# One bounded invocation. Native lockf serializes scheduled and manual work.
set -euo pipefail
umask 077
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C TZ=America/Chicago

backup_due() {
    local now=$1 last=$2 hour=$3 today=$4 last_day=$5
    (( last <= now )) || return 2
    (( last == 0 || now - last >= 86400 )) && return 0
    # Calendar run: once per Chicago day, even when yesterday finished after 03:00.
    # RunAtLoad outside the 03:00 hour only catches up after a full 24 hours.
    [[ $hour == 03 && $today != "$last_day" ]]
}

main() {
    [[ $# == 0 || ( $# == 1 && $1 == --now ) ]] || return 64
    [[ $(id -u) == 501 && $(hostname -s) == ambrosia ]] || return 77
    local lib=/Users/avirut/.local/lib/kroacnet-backup
    local config=/Users/avirut/.config/kroacnet-backup
    local base=/Users/avirut/Documents/Projects/kroacnet/private/backups/restic/stage
    [[ -d $base && ! -L $base && $(stat -f '%u:%Lp' "$base") == 501:700 ]] || return 77
    [[ ! -L $base/operation.lock ]] || return 77
    exec 9>"$base/operation.lock"
    /usr/bin/lockf -s -t 0 9 || return $?
    local now last=0 stamp last_day=none due
    now=$(date +%s)
    if [[ -f $base/apps/last-success ]]; then
        IFS= read -r stamp < "$base/apps/last-success"
        last=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$stamp" +%s 2>/dev/null) || return 65
        last_day=$(date -r "$last" +%F)
    fi
    if [[ ${1:-} != --now ]]; then
        if backup_due "$now" "$last" "$(date +%H)" "$(date +%F)" "$last_day"; then
            :
        else
            due=$?
            [[ $due == 1 ]] && return 0
            return 65
        fi
    fi
    # Child workers have their own timeouts in prepare.sh; no retry loop here.
    "$lib/run-backup.sh" "$config/restic.env" "$config/host.sh" apps
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
