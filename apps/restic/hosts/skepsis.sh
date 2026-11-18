MACHINE_HOST=skepsis
BACKUP_HOST=skepsis
ROOT_UUID=c119f6b9-f053-448d-9de1-7bd60c46502f
FORBIDDEN_ROOTS=(/mnt /media /run/media /srv/nas /home/avirut/selfhosted/data/books /home/avirut/selfhosted/data/storyteller)
EXCLUDES=(node_modules/ __pycache__/ .venv/ .cache/ .svelte-kit/ .next/ target/ '*.log' '*-wal' '*-shm' '*-journal' '*.sqlite-backup' 'logs_*.sqlite' models_cache.json)
prepare_embral() {
    postgres_optional embral-db
    copy_optional /home/avirut/embral build/ dist/ backups/
}
prepare_apps() {
    postgres_optional authentik-postgresql
    postgres_optional qm-postgres-1
    postgres_optional tandoor-db
    postgres_optional sparkyfitness-db
    postgres_optional paseo-hub-db
    copy_optional /home/avirut/selfhosted /data/ /backups/ /work/
    copy_optional /home/avirut/qm /build/ /var/backups/ /var/logs/ /var/cache/ '/var/books/oathbringer-repair/*.epub'
    copy_optional /home/avirut/kroacnet /scratch/ /private/
    copy_optional /home/avirut/.config/systemd/user
    copy_optional /home/avirut/.codex /plugins/ /packages/ /cache/ /tmp/ /.tmp/ /shell_snapshots/ /thread-writer-locks/ /tui-thread-reference-capabilities/ /app-server-control/ /models_cache.json '/logs_*.sqlite' /version.json
    copy_optional /home/avirut/selfhosted/data/actual
    copy_optional /home/avirut/selfhosted/data/authentik /database/
    copy_optional /home/avirut/selfhosted/data/caddy
    copy_optional /home/avirut/selfhosted/data/grocy/config /log/ /data/storage/cache/
    copy_optional /home/avirut/selfhosted/data/tandoor/mediafiles
    copy_optional /home/avirut/selfhosted/data/sparkyfitness/uploads
    copy_optional /home/avirut/selfhosted/data/termix
    copy_optional /etc/nut
    copy_source /etc/systemd/system 
    copy_source /etc/fstab 
    copy_source /etc/hostname 
    copy_source /etc/hosts 
    copy_source /etc/kroacnet-backup 
    copy_optional /home/avirut/.paseo /models/ /runtime/ '*.log' '*.log.*' '*.log.txt' /paseo.pid '*.sock' '*.lock' '*.claim'
    copy_optional /home/avirut/.claude /backups/ /cache/ /downloads/ /plugins/ /session-env/ /shell-snapshots/ /sessions/
    copy_optional /home/avirut/.config/kroacnet/paseo-web/hosts.json
    copy_optional /home/avirut/.claude.json
}
