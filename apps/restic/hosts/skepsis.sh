# Reviewed source selections; credentials are supplied separately.
MACHINE_HOST=skepsis
BACKUP_HOST=skepsis
ROOT_UUID=c119f6b9-f053-448d-9de1-7bd60c46502f
EXCLUDES=(node_modules/ __pycache__/ .venv/ .cache/ .svelte-kit/ .next/ target/ '*.log' '*-wal' '*-shm' '*-journal' '*.sqlite-backup' 'logs_*.sqlite' models_cache.json)
prepare_embral() {
    postgres embral-db
    copy_source /home/avirut/embral build/ dist/ backups/
}
prepare_apps() {
    postgres authentik-postgresql
    postgres qm-postgres-1
    postgres tandoor-db
    postgres sparkyfitness-db
    postgres paseo-hub-db
    copy_source /home/avirut/selfhosted /data/ /backups/ /work/
    copy_source /home/avirut/qm /build/ /var/backups/ /var/logs/ /var/cache/ '/var/books/oathbringer-repair/*.epub'
    copy_source /home/avirut/kroacnet /scratch/ /private/
    copy_source /home/avirut/.config/systemd/user 
    copy_source /home/avirut/.codex /plugins/ /packages/ /cache/ /tmp/ /.tmp/ /shell_snapshots/ /thread-writer-locks/ /tui-thread-reference-capabilities/ /app-server-control/ /models_cache.json '/logs_*.sqlite' /version.json
    copy_source /home/avirut/selfhosted/data/actual 
    copy_source /home/avirut/selfhosted/data/authentik /database/
    copy_source /home/avirut/selfhosted/data/caddy 
    copy_source /home/avirut/selfhosted/data/grocy/config /log/ /data/storage/cache/
    copy_source /home/avirut/selfhosted/data/tandoor/mediafiles 
    copy_source /home/avirut/selfhosted/data/sparkyfitness/uploads 
    copy_source /home/avirut/selfhosted/data/termix 
    copy_source /etc/nut 
    copy_source /etc/systemd/system 
    copy_source /etc/fstab 
    copy_source /etc/hostname 
    copy_source /etc/hosts 
    copy_source /etc/kroacnet-backup 
    copy_source /home/avirut/.paseo /models/ /runtime/ '*.log' '*.log.*' '*.log.txt' /paseo.pid '*.sock' '*.lock' '*.claim'
    copy_source /home/avirut/.claude /backups/ /cache/ /downloads/ /plugins/ /session-env/ /shell-snapshots/ /sessions/
    copy_source /home/avirut/.config/kroacnet/paseo-web/hosts.json 
    copy_source /home/avirut/.claude.json 
}
