# Reviewed source selections; credentials are supplied separately.
MACHINE_HOST=sophon-gpu
BACKUP_HOST=sophon-gpu
ROOT_UUID=1bfefdfb-34c9-46c7-854f-399d0a1dea04
FORBIDDEN_ROOTS=(/mnt /media /run/media /srv/nas /home/avirut/selfhosted/data/ollama /home/avirut/Games /home/avirut/.local/share/ghost-story/models /home/avirut/.local/share/eden/nand/user/Contents /home/avirut/.local/share/eden/nand/system/Contents)
EXCLUDES=(node_modules/ __pycache__/ .venv/ .cache/ .svelte-kit/ .next/ target/ '*.log' '*-wal' '*-shm' '*-journal' '*.sqlite-backup' 'logs_*.sqlite' models_cache.json '*.log.*')
prepare_apps() {
    copy_source /home/avirut/selfhosted /data/ /backups/ /work/
    copy_source /etc/systemd/system 
    copy_source /etc/fstab 
    copy_source /etc/hostname 
    copy_source /etc/hosts 
    copy_source /etc/kroacnet-backup 
    copy_source /home/avirut/.config/eden logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.config/sunshine logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.config/skyphos-agent logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.config/systemd/user logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.config/autostart logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.local/state/skyphos-agent logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*' '*.lock'
    copy_source /home/avirut/.local/bin 
    copy_source /etc/X11/xorg.conf.d 
    copy_source /etc/lightdm 
    copy_stable /home/avirut/.local/share/eden/nand/user/save logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_stable /home/avirut/.local/share/eden/nand/system/save logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_stable /home/avirut/.local/share/eden/sdmc/switch logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.local/share/eden/load logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.local/share/eden/keys logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.local/share/eden/tas logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/.local/share/eden/play_time logs/ log/ Logs/ cache/ Cache/ Backups/ backups/ backup/ '*.backup' '*.log.*'
    copy_source /home/avirut/skyphos/assets 
}
