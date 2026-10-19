# Reviewed source selections; credentials are supplied separately.
MACHINE_HOST=sophon-apps
BACKUP_HOST=sophon-media
ROOT_UUID=aa2fd39f-c27d-4a91-ab92-ddc86f5c6930
EXTERNAL_ROOM_UUID=591FA9A771A1BE2A
EXCLUDES=(node_modules/ __pycache__/ .venv/ .cache/ .svelte-kit/ .next/ target/ '*.log' '*-wal' '*-shm' '*-journal' '*.sqlite-backup' 'logs_*.sqlite' models_cache.json '*.log.*' logs.db 'logs.db-*' logs.sqlite 'logs.sqlite-*')
prepare_apps() {
    postgres bookorbit-db
    copy_source /home/avirut/selfhosted /data/ /backups/ /work/
    copy_source /etc/systemd/system 
    copy_source /etc/fstab 
    copy_source /etc/hostname 
    copy_source /etc/hosts 
    copy_source /etc/kroacnet-backup 
    copy_source /home/avirut/selfhosted/data/qbittorrent/appdata logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/radarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/sonarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/prowlarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/bazarr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/autobrr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/sabnzbd/config logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/shelfmark/config logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/karaoke-eternal logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/pikaraoke logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/book-downloads logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/storyteller logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /assets/ /qm-imports/ /image-cache/ /.autoimport/
    copy_source /home/avirut/selfhosted/data/bookorbit/app /book-bucket/ /covers/
    copy_source /home/avirut/selfhosted/data/jellyfin/config logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /metadata/ transcodes/ SQLiteBackups/ /data/subtitles/
    copy_source /home/avirut/selfhosted/data/nightingale logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /vendor/ /models/ /videos/ /.local/
    copy_source /home/avirut/selfhosted/data/homarr/appdata logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' /redis/
    copy_source /selfhosted/data/seerr logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/selfhosted/data/aiostreams/db.sqlite 
    copy_source /home/avirut/selfhosted/data/aiostreams/instance-id 
    copy_source /home/avirut/selfhosted/data/aiostreams-stremthru/stremthru.db 
    copy_source /home/avirut/.config/okearak 
    copy_source /mnt/data/media/okearak/state/room.db 
}
