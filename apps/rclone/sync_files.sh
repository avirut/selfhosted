#!/bin/sh
rclone sync /data DEFAULT:${BUCKET_NAME} --progress --fast-list --rc-addr /tmp/rclone-backup-running

wget -qO- ${UPTIME_KUMA_URL}/api/push/${UPTIME_KUMA_CODE}?status=up&msg=success&ping= &> /dev/null