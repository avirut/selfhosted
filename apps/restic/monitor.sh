#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 1 ]] || { echo 'Usage: monitor.sh ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/health.sh"
STATE=$BACKUP_STATE/shared-monitor
mkdir -p "$STATE"
exec 8>"$STATE/lock"; flock -n 8 || exit 0
now=$(date +%s)

owner_message() (
    cd /home/avirut/qm
    runuser -u avirut -- /home/avirut/.local/bin/node scripts/owner-message.ts "$1"
)

cancel_notice() {
    local key=$1 status retry
    [[ $key =~ ^backups:[a-z0-9.-]+:[0-9]+$ ]] || return 0
    retry=$STATE/withdraw-${key//:/-}.request
    status=$(jq -n --arg key "$key" '{requestKey:$key}' | owner_message cancel | jq -er '.status')
    if [[ $status == sending ]]; then
        printf '%s\n' "$key" > "$retry.new"
        mv -- "$retry.new" "$retry"
    elif [[ -f $retry ]]; then
        rm -- "$retry"
    fi
}

save_notice() {
    printf '%s %s %s %s\n' "$2" "$now" "$3" "$4" > "$STATE/$1.state.new"
    mv -- "$STATE/$1.state.new" "$STATE/$1.state"
}

report() {
    local key=$1 condition=$2 detail=$3 repeat=${4:-86400}
    local previous='' sent=0 old_key='' old_detail='' notice
    local state=$STATE/$key.state pending=$STATE/$key.pending.json
    if [[ -f $state ]]; then read -r previous sent old_key old_detail < "$state"; fi
    if [[ $previous && ! $old_key ]]; then old_key=backups:$key:$sent; fi
    if [[ -f $pending ]]; then
        notice=$(jq -r '.request.requestKey // ""' "$pending" 2>/dev/null || true)
        if jq -e --arg condition "$condition" --arg detail "$detail" \
            '.condition == $condition and .detail == $detail' "$pending" >/dev/null 2>&1; then
            jq '.request' "$pending" | owner_message enqueue >/dev/null
            save_notice "$key" "$condition" "$notice" "$detail"
            rm -- "$pending"
            return
        fi
        cancel_notice "$notice"
        rm -- "$pending"
    fi
    if [[ $condition == quiet ]]; then
        if [[ $old_key && $old_key != - ]]; then
            cancel_notice "$old_key"
            save_notice "$key" "$previous" - "$old_detail"
        fi
        return
    fi
    if [[ $condition == "$previous" ]] &&
        { [[ $condition == healthy ]] ||
            { [[ $old_key != - && $detail == "$old_detail" ]] && (( repeat == 0 || now - sent < repeat )); }; }; then
        return
    fi
    cancel_notice "$old_key"
    if [[ ! $previous && $condition == healthy ]]; then
        save_notice "$key" "$condition" - "$detail"
        return
    fi
    notice=backups:$key:$(date +%s%N)
    jq -n --arg requestKey "$notice" --arg text "Backups: $key is $condition. $detail" \
        --arg condition "$condition" --arg detail "$detail" \
        '{condition:$condition,detail:$detail,request:{requestKey:$requestKey,text:$text}}' > "$pending.new"
    mv -- "$pending.new" "$pending"
    jq '.request' "$pending" | owner_message enqueue >/dev/null
    save_notice "$key" "$condition" "$notice" "$detail"
    rm -- "$pending"
}

maintenance_description() {
    case $1 in
        lock) echo 'Another backup operation held the maintenance lock.';;
        catalogue-*) catalogue_description "${1#catalogue-}";;
        retention) echo 'Restic could not preview the retention plan.';;
        config) echo 'Maintenance could not load the repository configuration.';;
        precheck) echo 'Pre-prune repository data verification failed in Restic.';;
        prune) echo 'Restic failed while applying retention and pruning.';;
        postcheck) echo 'Repository metadata verification failed after pruning.';;
        record) echo 'Maintenance could not save its completion record.';;
        *) echo 'Maintenance stopped before completing the repository checks.';;
    esac
}

verification_description() {
    local set=${2:-the selected backup}
    case $1 in
        lock) echo 'Another operation blocked the sample restore check.';;
        config) echo 'Restore verification could not load repository configuration.';;
        catalogue) echo 'Restic could not list snapshots for verification.';;
        missing) echo "No snapshot was available for $set.";;
        inventory) echo "Restic could not list files for $set.";;
        sample) echo "No suitable restore sample exists for $set.";;
        restore) echo "Restic could not restore samples for $set.";;
        validate) echo "Restored samples failed validation for $set.";;
        record) echo 'Restore verification could not save its completion record.';;
        *) echo 'Restore verification exited before recording a success.';;
    esac
}

for obsolete in "$STATE"/withdraw-backups-*.request; do
    if [[ -f $obsolete ]]; then
        read -r key < "$obsolete"
        cancel_notice "$key"
    fi
done
report maintenance-age quiet '' 0
catalogue=$STATE/snapshots.json
if "$SCRIPT_DIR/list-snapshots.sh" "$1" --json > "$catalogue.new"; then
    if ! jq -e 'type == "array"' "$catalogue.new" >/dev/null; then
        report repository unavailable "$(catalogue_description invalid)"
        exit 1
    fi
else
    report repository unavailable "$(catalogue_description "$?")"
    exit 1
fi
mv -- "$catalogue.new" "$catalogue"
report repository healthy 'Restic can list the repository snapshots again.'

blocker=''
for set in "${BACKUP_SETS[@]}"; do
    key=${set//\//-}
    condition=$(snapshot_status "$catalogue" "$set" "$now")
    case $condition in
        healthy) detail='A recent successful snapshot is available again.';;
        missing) condition=stale; detail='No successful snapshot exists for this backup.';;
        stale) detail='Latest successful snapshot is over 30 hours old.';;
        invalid) condition=unavailable; detail='The latest snapshot has an unreadable timestamp.';;
    esac
    if [[ $condition != healthy && ! $blocker ]]; then blocker="No current snapshot is available for $key."; fi
    if [[ $set == skepsis/* && -f $BACKUP_STATE/${set##*/}/result ]]; then
        read -r outcome _ stage < "$BACKUP_STATE/${set##*/}/result"
        if [[ $outcome == failed ]]; then
            condition=failed
            case $stage in
                lock) detail='Another operation blocked this backup from starting.';;
                source) detail='A required host path is missing or invalid.';;
                mount) detail='A backup source is on an unexpected filesystem.';;
                sqlite) detail='SQLite backup or database integrity verification failed.';;
                conversation) detail='Conversation history changed or contained invalid records.';;
                empty) detail='Preparation produced no files to back up.';;
                prepare) detail='Backup stopped while preparing application data.';;
                upload) detail='Restic could not upload a complete snapshot.';;
                record) detail='The backup could not save its completion record.';;
                *) detail='The backup job did not complete successfully.';;
            esac
        fi
    fi
    report "$key" "$condition" "$detail"
done

restored=$(read_epoch "$BACKUP_STATE/restore-success" || echo 0)
restore_blocker=''
if (( restored == 0 )); then
    restore_blocker='No successful sample restore has been recorded.'
elif (( now - restored >= RESTORE_MAX_AGE )); then
    restore_blocker='The last verified restore exceeds 40 days.'
fi
if [[ $restore_blocker ]]; then
    report restore-age stale "$restore_blocker"
else
    report restore-age healthy 'A recent sample restore completed and passed verification.'
fi

outcome='' stage='' subject=''
if [[ -f $BACKUP_STATE/verify-result ]]; then
    read -r outcome _ stage subject < "$BACKUP_STATE/verify-result"
fi
if [[ $outcome == failed ]] || systemctl is-failed --quiet restic-verify.service; then
    report verify failed "$(verification_description "$stage" "$subject")"
elif [[ $outcome != running ]]; then
    report verify healthy 'The sample restore verification finished successfully.'
fi

outcome='' stage='' subject='' stamp=''
if [[ -f $BACKUP_STATE/maintenance-result ]]; then
    read -r outcome stamp stage subject < "$BACKUP_STATE/maintenance-result"
fi
completed=$(read_epoch "$BACKUP_STATE/maintenance-success" || echo 0)
attempted=0
if [[ $stamp ]]; then attempted=$(date -d "$stamp" +%s 2>/dev/null || echo 0); fi
failure=''
if (( completed >= attempted && completed > 0 )) && [[ $outcome ]]; then
    outcome=success
elif [[ $outcome == failed ]] || { [[ $outcome == running ]] && systemctl is-failed --quiet restic-maintenance.service; }; then
    case $stage in
        catalogue-*) outcome=deferred;;
        *) outcome=failed; failure=$(maintenance_description "$stage");;
    esac
fi
[[ $outcome != running ]] || exit 0
if (( completed == 0 || now - completed >= MAINTENANCE_MAX_AGE )); then
    if [[ $restore_blocker || $blocker || $failure ]]; then
        report maintenance overdue "${restore_blocker:-${blocker:-$failure}}" 0
    elif (( completed == 0 )); then
        report maintenance overdue 'No successful repository maintenance run is recorded.' 0
    else
        report maintenance overdue 'No successful maintenance run in nine days.' 0
    fi
elif [[ $failure ]]; then
    report maintenance failed "$failure" 0
elif [[ $outcome == success ]]; then
    report maintenance healthy 'Repository maintenance completed successfully in the quiet window.' 0
else
    report maintenance quiet '' 0
fi
