#!/bin/bash

# load environment variables from .env
set -o allexport
source .env
set +o allexport

# list snapshots
restic -r b2:${B2_BUCKET_NAME} snapshots

echo "This is a full list of snapshots. To filter by repository and perform other important operations, see the restic documentation: https://restic.readthedocs.io/en/stable/045_working_with_repos.html"