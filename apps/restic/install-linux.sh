#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 && $# == 2 ]] || { echo 'Usage: sudo install-linux.sh HOST ENV_FILE' >&2; exit 2; }
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
host=$1; envfile=$2
case $host in skepsis) time=03:30;; sophon-media) time=03:50;; sophon-gpu) time=04:10;; sophon) time=04:30;; sophon-agent) time=04:40;; *) exit 2;; esac
for tool in restic sqlite3 rsync jq timeout flock setpriv; do command -v "$tool" >/dev/null; done
install -d -m 700 /etc/kroacnet-backup /var/lib/kroacnet-backup
install -d -m 755 /opt/kroacnet-backup
if [[ $(realpath "$envfile") != /etc/kroacnet-backup/selfhosted.env ]]; then install -m 600 "$envfile" /etc/kroacnet-backup/selfhosted.env; fi
install -m 600 "$SCRIPT_DIR/hosts/$host.sh" /etc/kroacnet-backup/host.sh
install -m 600 "$SCRIPT_DIR/hosts/$host.excludes" /etc/kroacnet-backup/host.excludes
install -m 644 "$SCRIPT_DIR/excludes.txt" /opt/kroacnet-backup/
for script in common backup list-snapshots restore remove-old run-backup; do install -m 755 "$SCRIPT_DIR/$script.sh" /opt/kroacnet-backup/; done
install -m 644 "$SCRIPT_DIR/restic-backup@.service" "$SCRIPT_DIR/restic-apps.timer" /etc/systemd/system/
rm -rf /opt/kroacnet-backup/prepare.sh /etc/systemd/system/restic-backup@apps.service.d /var/lib/kroacnet-backup/{apps,embral}/{payload,pending,previous}
install -d /etc/systemd/system/restic-apps.timer.d
printf '[Timer]\nOnCalendar=\nOnCalendar=*-*-* %s:00 America/Chicago\n' "$time" > /etc/systemd/system/restic-apps.timer.d/schedule.conf
if [[ $host == skepsis ]]; then
    for script in health maintenance monitor verify; do install -m 755 "$SCRIPT_DIR/$script.sh" /opt/kroacnet-backup/; done
    for unit in restic-embral.timer restic-maintenance.service restic-maintenance.timer restic-monitor.service restic-monitor.timer restic-verify.service restic-verify.timer; do install -m 644 "$SCRIPT_DIR/$unit" /etc/systemd/system/; done
    install -d /etc/systemd/system/restic-backup@.service.d
    install -m 644 "$SCRIPT_DIR/restic-backup-alerts.conf" /etc/systemd/system/restic-backup@.service.d/alerts.conf
fi
systemctl daemon-reload
echo 'Installed. Qualify the backup service before enabling the daily timers.'
