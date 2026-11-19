MACHINE_HOST=sophon-apps
BACKUP_HOST=sophon-media
ROOT_UUID=aa2fd39f-c27d-4a91-ab92-ddc86f5c6930
EXTERNAL_ROOM_UUID=591FA9A771A1BE2A
FORBIDDEN_ROOTS=(/mnt /media /run/media /srv/nas /home/avirut/selfhosted/data/books /home/avirut/selfhosted/data/bookorbit/postgres /home/avirut/selfhosted/data/nightingale/vendor)
EXCLUDES=(node_modules/ __pycache__/ .venv/ .cache/ .svelte-kit/ .next/ target/ '*.log' '*-wal' '*-shm' '*-journal' '*.sqlite-backup' 'logs_*.sqlite' models_cache.json '*.log.*' logs.db 'logs.db-*' logs.sqlite 'logs.sqlite-*')
pelican_command() {
    local token
    token=$(awk '$1 == "token:" {print $2}' /etc/pelican/config.yml | tr -d '\047\042')
    curl -fsS -o /dev/null --max-time 15 -X POST -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data "{\"commands\":[$2]}" "http://127.0.0.1:8121/api/servers/$1/commands"
}
pelican_save_on() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if pelican_command "$1" '"save-on"'; then return 0; fi
        sleep 3
    done
    echo "Minecraft autosave was not re-enabled for $1" >&2
    return 1
}
copy_pelican_server() {
    local volume=$1 uuid=${1##*/} log=$1/logs/latest.log lines=0 attempt
    local skip=(/cache/ /libraries/ /versions/ /logs/ /crash-reports/)
    if [[ -f $log ]]; then lines=$(wc -l < "$log"); fi
    if pelican_command "$uuid" '"save-off","save-all flush"' 2>/dev/null; then
        (
            trap 'pelican_save_on "$uuid" || exit 1' EXIT
            for attempt in {1..60}; do
                if grep -q 'Saved the game' < <(tail -n "+$((lines + 1))" "$log"); then break; fi
                (( attempt < 60 )) || fail 'Minecraft save did not finish'
                sleep 1
            done
            copy_source "$volume" "${skip[@]}"
        )
    else
        copy_source "$volume" "${skip[@]}"
    fi
}
prepare_apps() {
    postgres_optional bookorbit-db
    copy_optional /home/avirut/selfhosted /data/ /backups/ /work/
    copy_source /etc/systemd/system 
    copy_source /etc/fstab 
    copy_source /etc/hostname 
    copy_source /etc/hosts 
    copy_source /etc/kroacnet-backup 
    copy_optional /home/avirut/selfhosted/data/qbittorrent/appdata logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/radarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/sonarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/prowlarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/bazarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/autobrr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/sabnzbd/config logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/shelfmark/config logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/karaoke-eternal logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/pikaraoke logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/book-downloads logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/storyteller logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /assets/ /qm-imports/ /image-cache/ /.autoimport/
    copy_optional /home/avirut/selfhosted/data/bookorbit/app /book-bucket/ /covers/
    copy_optional /home/avirut/selfhosted/data/jellyfin/config logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /metadata/ transcodes/ SQLiteBackups/ /data/subtitles/
    copy_optional /home/avirut/selfhosted/data/nightingale logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /vendor/ /models/ /videos/ /.local/
    copy_optional /home/avirut/selfhosted/data/homarr/appdata logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /redis/
    copy_optional /selfhosted/data/seerr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_optional /home/avirut/selfhosted/data/aiostreams/db.sqlite
    copy_optional /home/avirut/selfhosted/data/aiostreams/instance-id
    copy_optional /home/avirut/selfhosted/data/aiostreams-stremthru/stremthru.db
    copy_optional /home/avirut/.config/okearak
    copy_optional /mnt/data/media/okearak/state/room.db
    copy_optional /home/avirut/selfhosted/data/pelican /caddy/ /panel-logs/ /panel/
    copy_optional /var/lib/pelican-panel
    copy_optional /etc/pelican
    local server
    for server in /var/lib/pelican/volumes/*/; do
        if [[ -d $server ]]; then copy_pelican_server "${server%/}"; fi
    done
}
