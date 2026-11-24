BACKUP_HOST=sophon-media
profile_apps() {
    ROOTS=(/ /mnt/data/media/okearak/library/.versions /mnt/data/media/okearak/state)
}
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
    return 1
}
pelican_saved() {
    local attempt
    for attempt in {1..60}; do
        if tail -n "+$(($2 + 1))" "$1" | grep -q 'Saved the game'; then return 0; fi
        sleep 1
    done
    return 1
}
prepare_host() {
    local volume uuid log lines
    for volume in /var/lib/pelican/volumes/*/; do
        volume=${volume%/} uuid=$(basename "$volume") log=$volume/logs/latest.log
        [[ -f $log ]] || continue
        lines=$(wc -l < "$log")
        pelican_command "$uuid" '"save-off","save-all flush"' 2>/dev/null || continue
        (
            trap 'pelican_save_on "$uuid" || exit 1' EXIT
            mkdir -p "$STAGE/files$volume"
            if pelican_saved "$log" "$lines" && rsync -a --exclude=/cache --exclude=/libraries --exclude=/logs --exclude=/versions "$volume/" "$STAGE/files$volume/"; then
                literal "$volume" >> "$EXCLUDES"
            else
                rm -rf "$STAGE/files$volume"
                note "kept live copy: $volume"
            fi
        ) || failures+=("autosave:$uuid")
    done
}
