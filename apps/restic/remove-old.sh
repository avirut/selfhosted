#!/bin/bash

# load environment variables from .env
set -o allexport
source .env
set +o allexport

# remove old backups based on policy specified in .env
restic forget -r b2:${B2_BUCKET_NAME} --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY --keep-yearly $KEEP_YEARLY --prune

# check the repository for errors
restic check -r b2:${B2_BUCKET_NAME}