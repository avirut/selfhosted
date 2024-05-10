#!/bin/bash

# import environment variables from file provided as argument
set -o allexport
source $1
set +o allexport

# backup from local directory to repository as specified in .env
restic -r s3:${S3_ENDPOINT} --verbose backup ${BACKUP_DIR} --exclude-file="./excludes.txt"
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