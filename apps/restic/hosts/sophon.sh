# Reviewed source selections; credentials are supplied separately.
MACHINE_HOST=sophon
BACKUP_HOST=sophon
ROOT_SOURCE=rpool/ROOT/pve-1
ROOT_FSTYPE=zfs
FORBIDDEN_ROOTS=(/mnt /media /run/media /srv/nas)
EXCLUDES=(node_modules/ __pycache__/ .venv/ .cache/ .svelte-kit/ .next/ target/ '*.log' '*-wal' '*-shm' '*-journal' '*.sqlite-backup' 'logs_*.sqlite' models_cache.json '*.log.*')
prepare_apps() {
    copy_source /etc/systemd/system 
    copy_source /etc/fstab 
    copy_source /etc/hostname 
    copy_source /etc/hosts 
    copy_source /etc/kroacnet-backup 
    copy_source /var/lib/pve-cluster/config.db 
    copy_source /etc/network/interfaces 
    copy_source /etc/network/interfaces.d 
    copy_source /etc/kernel/cmdline 
    copy_source /etc/kernel/proxmox-boot-uuids 
    copy_source /etc/modprobe.d 
    copy_source /etc/sysctl.d 
    copy_source /etc/modules 
    copy_source /home/avirut/kroacnet /scratch/ /private/
    copy_source /home/avirut/.paseo /models/ /runtime/ /paseo.pid '*.log.txt' '*.lock'
    copy_source /home/avirut/.codex/sessions 
    copy_source /home/avirut/.codex/archived_sessions 
    copy_source /home/avirut/.codex/session_index.jsonl 
    copy_source /home/avirut/.codex/config.toml 
    copy_source /home/avirut/.codex/auth.json 
    copy_source /home/avirut/.codex/installation_id 
    copy_source /home/avirut/.codex/state_5.sqlite 
    copy_source /home/avirut/.codex/thread_history_1.sqlite 
    copy_source /home/avirut/.codex/queue_1.sqlite 
    copy_source /home/avirut/.codex/goals_1.sqlite 
    copy_source /home/avirut/.codex/memories_1.sqlite 
    copy_source /home/avirut/.codex/artifacts 
    copy_source /home/avirut/.codex/visualizations 
    copy_source /home/avirut/.codex/attachments '*.zip'
    copy_source /home/avirut/.config/systemd/user/paseo.service 
    copy_source /home/avirut/.local/state/kroacnet-pm/20261014/connections.json 
    copy_source /home/avirut/skyphos /.git/ /artifacts/ bin/ obj/ dist/ build/ coverage/ /ui/.pnpm-store/
}
