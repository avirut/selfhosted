#!/bin/bash

# import environment variables from file provided as argument
set -o allexport
source $1
set +o allexport

# list snapshots
restic -r s3:${S3_ENDPOINT} snapshots

echo "This is a full list of snapshots. To filter by repository and perform other important operations, see the restic documentation: https://restic.readthedocs.io/en/stable/045_working_with_repos.html"