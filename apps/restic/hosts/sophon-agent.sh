MACHINE_HOST=sophon-agent
BACKUP_HOST=sophon-agent
ROOT_UUID=0f7601ca-426f-4206-94f1-1a1ed980ac81
FORBIDDEN_ROOTS=(/mnt /media /run/media /srv/nas /home/avirut/.hermes/hermes-agent /home/avirut/.hermes/tools /home/avirut/.hermes/cache /home/avirut/.hermes/installs /home/avirut/.config/botscreen-chrome)
EXCLUDES=(node_modules/ __pycache__/ .venv/ .cache/ '*.log' '*-wal' '*-shm' '*-journal' '*.log.*')
prepare_apps() {
    copy_source /etc/systemd/system 
    copy_source /etc/hostname 
    copy_source /etc/hosts 
    copy_source /etc/kroacnet-backup 
    copy_optional /etc/apt/sources.list.d
    copy_optional /usr/local/bin/skepsis
    copy_source /home/avirut/.hermes hermes-agent/ tools/ cache/ installs/ logs/ runtime/ telemetry/ image_cache/ bot-desktop/browser-profile/ models_dev_cache.json
    copy_optional /home/avirut/.claude projects/ file-history/ shell-snapshots/ todos/ statsig/ ide/ logs/ cache/
    copy_optional /home/avirut/.claude.json
    copy_optional /home/avirut/.google_workspace_mcp
    copy_optional /home/avirut/.config/workspace-mcp
    copy_optional /home/avirut/.config/gws-inspire
    copy_optional /home/avirut/.config/systemd/user
    copy_optional /home/avirut/.local/bin/gws-inspire
    copy_optional /home/avirut/.local/bin/qm-docs-sync
    copy_optional /home/avirut/.local/state/qm-mirror-edits
}
