#!/bin/bash

# load environment variables from .env
set -o allexport
source .env
set +o allexport

# backup from local directory to repository as specified in .env
restic -r b2:${B2_BUCKET_NAME} --verbose backup ${BACKUP_DIR} --exclude-file="./excludes.txt"
restic_status=$?

# describe how the backup went
# TODO: replace with healthcheck/ntfy
if [ $restic_status -eq 0 ]; then
    echo "success"
    curl ${UPTIME_KUMA_URL}/api/push/${UPTIME_KUMA_CODE}?status=up&msg=success&ping=
elif [ $restic_status -eq 1 ]; then
    echo "failure"
    curl ${UPTIME_KUMA_URL}/api/push/${UPTIME_KUMA_CODE}?status=down&msg=failure&ping=
elif [ $restic_status -eq 3 ]; then
    echo "incomplete"
    curl ${UPTIME_KUMA_URL}/api/push/${UPTIME_KUMA_CODE}?status=down&msg=incomplete&ping=
else
    echo "unknown"
    curl ${UPTIME_KUMA_URL}/api/push/${UPTIME_KUMA_CODE}?status=down&msg=unknown&ping=
fi