#!/usr/bin/env bash
# Prepare selected files and logical database exports; never upload an old stage.
set -euo pipefail
umask 077
[[ $# == 2 ]] || { echo 'Usage: prepare.sh HOST_CONFIG PROFILE' >&2; exit 2; }
CONFIG=$1; PROFILE=$2
BASE=/var/lib/kroacnet-backup
SQLITE=sqlite3
export LC_ALL=C
TIMEOUT=bounded
bounded() {
    local seconds=${1%s} child watcher status
    shift
    if command -v timeout >/dev/null; then timeout "${seconds}s" "$@"; return; fi
    "$@" & child=$!
    (sleep "$seconds"; kill -TERM "$child" 2>/dev/null) & watcher=$!
    if wait "$child"; then status=0; else status=$?; fi
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    return "$status"
}
fail() { echo "$*" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"
[[ $(hostname -s) == "$MACHINE_HOST" ]] || fail 'Wrong source host'
[[ $PROFILE == apps || $PROFILE == embral ]] || fail 'Unknown profile'
[[ $BASE == /* && $BASE != / ]] || fail 'Invalid staging root'
mkdir -p "$BASE/$PROFILE"
PENDING=$BASE/$PROFILE/pending
PAYLOAD=$BASE/$PROFILE/payload
[[ ! -L $PENDING && ! -L $PAYLOAD ]] || fail 'Indirect staging directory'
rm -rf "$PENDING"
mkdir -m 700 "$PENDING"
trap 'rm -rf "$PENDING"' EXIT
check_source() {
    local src=$1 actual
    [[ -e $src && ! -L $src ]] || fail "Required source unavailable: $src"
    case $(uname -s) in
    Linux)
        if [[ $src == /mnt/data/media/okearak/state/room.db && ${EXTERNAL_ROOM_UUID:-} ]]; then
            [[ $(findmnt -n -o UUID -T "$src") == "$EXTERNAL_ROOM_UUID" && $(findmnt -n -o FSTYPE -T "$src") == fuseblk ]] || fail 'Room database mount changed'
        else
            case $src in /mnt/*|/media/*|/run/media/*|/srv/nas/*) fail 'Unapproved external source';; esac
            if [[ ${ROOT_UUID:-} ]]; then
                [[ $(findmnt -n -o UUID -T "$src") == "$ROOT_UUID" ]] || fail 'Source filesystem changed'
            else
                actual=$(findmnt --nofsroot -n -o SOURCE -T "$src")
                [[ $actual == "$ROOT_SOURCE" && $(findmnt -n -o FSTYPE -T "$src") == "$ROOT_FSTYPE" ]] || fail 'Source dataset changed'
            fi
        fi;;
    esac
}
file_hash() {
    if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
sqlite_export() {
    local src=$1 dst=$2 scratch uid gid qdst
    scratch=$(mktemp -d /var/tmp/restic-sqlite.XXXXXX)
    if [[ $(uname -s) == Linux ]]; then
        uid=$(stat -c %u "$src"); gid=$(stat -c %g "$src")
    else
        uid=$(stat -f %u "$src"); gid=$(stat -f %g "$src")
    fi
    if (( EUID == 0 )); then chown "$uid:$gid" "$scratch"; fi
    qdst=${scratch//\'/\'\'}
    if (( EUID == 0 && uid != 0 )); then
        "$TIMEOUT" 120s setpriv --reuid="$uid" --regid="$gid" --clear-groups "$SQLITE" -batch -bail -readonly "$src" ".timeout 1500" ".backup '$qdst/database.sqlite'" || { rm -rf "$scratch"; fail 'SQLite online backup failed'; }
    else
        "$TIMEOUT" 120s "$SQLITE" -batch -bail -readonly "$src" ".timeout 1500" ".backup '$qdst/database.sqlite'" || { rm -rf "$scratch"; fail 'SQLite online backup failed'; }
    fi
    [[ $("$SQLITE" -batch -bail "$scratch/database.sqlite" 'PRAGMA integrity_check;') == ok ]] || { rm -rf "$scratch"; fail 'SQLite integrity check failed'; }
    cp "$scratch/database.sqlite" "$dst"
    if (( EUID == 0 )); then chown "$uid:$gid" "$dst"; fi
    chmod 600 "$dst"
    rm -rf "$scratch"
}
copy_source() {
    local src=$1 dst candidate original before after bytes tailbyte
    shift
    check_source "$src"
    dst=$PENDING/files$src
    mkdir -p "$(dirname "$dst")"
    local args=(-a -x --safe-links --no-devices --no-specials)
    local exclusion
    for exclusion in "${EXCLUDES[@]}" "$@"; do args+=("--exclude=$exclusion"); done
    if [[ -d $src ]]; then
        mkdir -p "$dst"
        "$TIMEOUT" 600s rsync "${args[@]}" "$src/" "$dst/"
    else
        "$TIMEOUT" 600s rsync "${args[@]}" "$src" "$dst"
    fi
    while IFS= read -r -d '' candidate; do
        original=$src
        if [[ -d $src ]]; then original=$src/${candidate#"$dst/"}; fi
        if [[ $(od -An -tx1 -N16 "$candidate" | tr -d ' \n') == 53514c69746520666f726d6174203300 ]]; then
            sqlite_export "$original" "$candidate"
        elif [[ $candidate == *.jsonl ]]; then
            # Capture a fixed complete-record prefix, validate it and detect rewrites.
            bytes=$(wc -c < "$candidate")
            before=$(file_hash "$candidate")
            head -c "$bytes" "$original" > "$candidate.check"
            after=$(file_hash "$candidate.check")
            [[ $before == "$after" ]] || fail 'Conversation changed while copying'
            rm "$candidate.check"
            if [[ $bytes -gt 0 ]]; then
                tailbyte=$(tail -c 1 "$candidate" | od -An -tu1 | tr -d ' ')
                if [[ $tailbyte != 10 ]]; then sed '$d' "$candidate" > "$candidate.complete"; mv "$candidate.complete" "$candidate"; fi
            fi
            "$TIMEOUT" 120s jq -c 'if type == "object" then empty else error("record is not an object") end' "$candidate" >/dev/null || fail 'Invalid conversation JSONL'
        fi
    done < <(find "$dst" -type f -print0)
}
copy_stable() {
    local src=$1 before after
    shift
    before=$(find "$src" -type f -exec cksum {} + | LC_ALL=C sort | cksum)
    copy_source "$src" "$@"
    after=$(find "$src" -type f -exec cksum {} + | LC_ALL=C sort | cksum)
    [[ $before == "$after" ]] || fail 'Application files changed during backup'
}
postgres() {
    local container=$1 user primary db directory names
    user=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" | sed -n 's/^POSTGRES_USER=//p')
    user=${user:-postgres}
    primary=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" | sed -n 's/^POSTGRES_DB=//p')
    primary=${primary:-$user}
    directory=$PENDING/databases/$container
    mkdir -p "$directory"
    docker exec --user postgres "$container" pg_dumpall -U "$user" --globals-only > "$directory/globals.sql"
    names=$(docker exec --user postgres "$container" psql -X -U "$user" -d "$primary" -Atc 'SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1')
    [[ $names ]] || fail 'PostgreSQL database list is empty'
    while IFS= read -r db; do
        [[ $db && $db != */* && $db != .* ]] || fail 'Invalid database name'
        docker exec --user postgres "$container" pg_dump -U "$user" -d "$db" -Fc > "$directory/$db.dump"
        docker exec -i "$container" pg_restore --list < "$directory/$db.dump" >/dev/null
    done <<< "$names"
}
"prepare_$PROFILE"
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PENDING/prepared-at"
# Generate hashes without interpreting application file contents.
(cd "$PENDING" && find . -type f ! -name SHA256SUMS -exec shasum -a 256 {} + > SHA256SUMS)
rm -rf "$BASE/$PROFILE/previous"
if [[ -d $PAYLOAD ]]; then mv "$PAYLOAD" "$BASE/$PROFILE/previous"; fi
mv "$PENDING" "$PAYLOAD"
trap - EXIT
