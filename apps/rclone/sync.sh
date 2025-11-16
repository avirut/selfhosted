#!/bin/bash
set -o allexport
source .env
set +o allexport

docker exec -t rclone rclone sync /data DEFAULT:${BUCKET_NAME} --progress --fast-list --rc-addr /tmp/rclone-backup-running
curl ${UPTIME_KUMA_URL}/api/push/${UPTIME_KUMA_CODE}?status=up&msg=success&ping= &> /dev/null