#!/bin/bash

# import environment variables from file provided as argument
set -o allexport
source $1
set +o allexport

# remove old backups based on policy specified in .env
restic forget -r s3:${S3_ENDPOINT} --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY --keep-yearly $KEEP_YEARLY --prune

# check the repository for errors
restic check -r s3:${S3_ENDPOINT}