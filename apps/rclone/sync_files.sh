#!/bin/bash
rclone sync /data DEFAULT:${BUCKET_NAME} --progress --fast-list --rc-addr /tmp/rclone-backup-running