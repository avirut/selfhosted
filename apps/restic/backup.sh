#!/bin/bash

# import environment variables from file provided as argument
set -o allexport
source $1
set +o allexport

# backup from local directory to repository as specified in .env
restic -r s3:${S3_ENDPOINT} --verbose backup ${BACKUP_DIR} --exclude-file="./excludes.txt"