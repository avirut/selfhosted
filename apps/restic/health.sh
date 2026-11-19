#!/usr/bin/env bash
BACKUP_STATE=/var/lib/kroacnet-backup
BACKUP_SETS=(skepsis/apps skepsis/embral sophon-media/apps sophon-gpu/apps sophon/apps ambrosia.local/apps chrysaora/apps)
SNAPSHOT_MAX_AGE=108000
RESTORE_MAX_AGE=3456000
MAINTENANCE_MAX_AGE=777600

read_epoch() {
    local stamp
    [[ -r $1 ]] && read -r stamp < "$1" && date -d "$stamp" +%s 2>/dev/null
}

snapshot_status() {
    local catalogue=$1 set=$2 now=$3 latest epoch
    if ! latest=$(jq -r --arg h "${set%/*}" --arg p "${set##*/}" \
        '[.[] | select(.hostname == $h and (.tags // [] | index($p)))] | max_by(.time) | .time // empty' "$catalogue"); then
        echo invalid
    elif [[ ! $latest ]]; then
        echo missing
    elif ! epoch=$(date -d "$latest" +%s 2>/dev/null); then
        echo invalid
    elif (( now - epoch >= SNAPSHOT_MAX_AGE )); then
        echo stale
    else
        echo healthy
    fi
}

write_result() {
    local path=$1 state=$2 stage=$3 subject=${4:-}
    printf '%s %s %s %s\n' "$state" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stage" "$subject" > "$path.new"
    mv -- "$path.new" "$path"
}

catalogue_description() {
    case $1 in
        10) echo 'Restic could not find the configured repository.';;
        11) echo 'A repository lock blocked the snapshot listing.';;
        12) echo 'Restic rejected the configured repository password.';;
        invalid) echo 'The repository returned an unreadable snapshot list.';;
        *) echo 'Restic could not list the repository snapshots.';;
    esac
}
