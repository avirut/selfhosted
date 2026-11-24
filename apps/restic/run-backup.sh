#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'Usage: run-backup.sh ENV HOST_CONFIG PROFILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=$1; HOST_CONFIG=$2; PROFILE=$3
BASE=/var/lib/kroacnet-backup
SQLITE=sqlite3
POSTGRES=.
failures=()
export LC_ALL=C
source "$HOST_CONFIG"
STATE=$BASE/$PROFILE
STAGE=$STATE/stage
EXCLUDES=$STATE/excludes
mkdir -p "$STATE"

literal() { printf '%s\n' "$1" | sed -e 's/[][\\*?]/\\&/g' -e 's/\$/$$/g'; }
note() { printf '%s\n' "$*" | tee -a "$STATE/notes" >&2; }
bounded() {
    local seconds=$1 child watcher status=0
    shift
    if command -v timeout >/dev/null; then timeout "$seconds" "$@"; return; fi
    "$@" & child=$!
    (sleep "$seconds"; kill -TERM "$child" 2>/dev/null) >/dev/null 2>&1 & watcher=$!
    wait "$child" || status=$?
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    return "$status"
}
sqlite_copy() {
    local src=$1 out=$2 scratch owner result=1
    local user=()
    scratch=$(mktemp -d /var/tmp/restic-sqlite.XXXXXX)
    if (( EUID == 0 )); then
        owner=$(stat -c %u:%g "$src")
        chown "$owner" "$scratch"
        if [[ ${owner%:*} != 0 ]]; then
            user=(setpriv --reuid="${owner%:*}" --regid="${owner#*:}" --clear-groups --inh-caps=+dac_read_search --ambient-caps=+dac_read_search)
        fi
    fi
    if bounded 300 ${user[@]+"${user[@]}"} "$SQLITE" -init /dev/null -batch -bail -readonly "$src" '.timeout 1500' \
            'BEGIN; SELECT count(*) FROM sqlite_schema;' ".backup '$scratch/copy'" 'ROLLBACK;' >/dev/null 2>&1 &&
        [[ $("$SQLITE" -init /dev/null -batch "$scratch/copy" 'PRAGMA quick_check;' 2>/dev/null) == ok ]]; then
        mkdir -p "$(dirname "$out")"
        if mv "$scratch/copy" "$out"; then result=0; fi
    fi
    rm -rf "$scratch"
    return "$result"
}
sqlite_candidates() {
    local pattern
    local skip=(-path "$BASE" -o -path "$BASE/*")
    while IFS= read -r pattern; do
        case $pattern in
            ''|'!'*) ;;
            /*) skip+=(-o -path "$pattern");;
            */*) skip+=(-o -path "*/$pattern");;
            *) skip+=(-o -name "$pattern");;
        esac
    done < "$EXCLUDES"
    find "${ROOTS[@]}" -xdev \( "${skip[@]}" \) -prune -o -type f -mtime -3 \
        \( -name '*.db' -o -name '*.db3' -o -name '*.sqlite' -o -name '*.sqlite3' -o -name '*-wal' \) -print0 2>/dev/null || true
}
prepare_sqlite() {
    local file suffix
    while IFS= read -r -d '' file; do
        file=${file%-wal}
        [[ -f $file && ! -e $STAGE/sqlite$file ]] || continue
        head -c 15 "$file" 2>/dev/null | grep -aq '^SQLite format 3$' || continue
        if sqlite_copy "$file" "$STAGE/sqlite$file"; then
            for suffix in '' -wal -shm -journal; do literal "$file$suffix"; done >> "$STATE/sqlite-excludes"
        else
            note "kept live copy: $file"
        fi
    done < <(sqlite_candidates)
    cat "$STATE/sqlite-excludes" >> "$EXCLUDES"
}
postgres_dump() {
    local container=$1 out=$STAGE/postgres/$1 user names db
    user=$(docker exec "$container" printenv POSTGRES_USER) || user=postgres
    names=$(docker exec --user postgres "$container" psql -X -U "$user" -d template1 -Atc 'SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1') || return 1
    mkdir -p "$out" || return 1
    docker exec --user postgres "$container" pg_dumpall -U "$user" --globals-only > "$out/globals.sql" || return 1
    while IFS= read -r db; do
        docker exec --user postgres "$container" pg_dump -U "$user" -d "$db" -Fc -Z0 > "$out/${db//\//_}.dump" || return 1
    done <<< "$names"
}
prepare_postgres() {
    local container mounts mount
    command -v docker >/dev/null || return 0
    for container in $(docker ps --filter status=running --format '{{.Names}}' 2>/dev/null | grep -E -- "$POSTGRES" || true); do
        mounts=$(docker inspect "$container" | jq -r '.[0] | ([.Config.Env[] | select(startswith("PGDATA=")) | .[7:]][0]) as $data
            | select($data) | "PGDATA", (.Mounts[] | select(.Destination as $at | ($data + "/") | startswith($at + "/")) | .Source)') || continue
        [[ $mounts ]] || continue
        if postgres_dump "$container"; then
            while IFS= read -r mount; do
                if [[ $mount == /* ]]; then literal "$mount" >> "$EXCLUDES"; fi
            done <<< "$mounts"
        else
            rm -rf "$STAGE/postgres/$container"
            note "PostgreSQL dump failed: $container"
            failures+=("postgres:$container")
        fi
    done
}

stage=lock
save_result() { printf '%s\n' "$*" > "$STATE/result.new"; mv "$STATE/result.new" "$STATE/result"; }
finish() {
    local status=$?
    if (( status != 0 )); then save_result failed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stage"; fi
}
trap finish EXIT
if command -v flock >/dev/null; then
    exec 9>"$BASE/operation.lock"
    flock -w 300 9
fi
stage=prepare
"profile_$PROFILE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
: > "$STATE/notes"
: > "$STATE/sqlite-excludes"
cat "$SCRIPT_DIR/excludes.txt" "${HOST_CONFIG%.sh}.excludes" > "$EXCLUDES"
prepare_sqlite
prepare_postgres
if declare -F prepare_host >/dev/null; then prepare_host; fi
tag=$PROFILE
if (( ${#failures[@]} )); then tag=$PROFILE-partial; fi
stage=upload
status=0
"$SCRIPT_DIR/backup.sh" "$ENV_FILE" "${ROOTS[@]}" --host "$BACKUP_HOST" --tag "$tag" --one-file-system --exclude-caches \
    --exclude-file "$EXCLUDES" --json > "$STATE/backup.jsonl" 2> "$STATE/unreadable.jsonl" || status=$?
if (( status != 0 && status != 3 )); then
    tail -n 5 "$STATE/unreadable.jsonl" >&2
    exit "$status"
fi
jq -e 'select(.message_type == "summary") | .snapshot_id' "$STATE/backup.jsonl" >/dev/null
if (( ${#failures[@]} )); then
    stage=${failures[0]%%:*}
    exit 1
fi
stage=record
date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE/last-success"
save_result success
