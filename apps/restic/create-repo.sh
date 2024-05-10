#!/bin/bash

# import environment variables from file provided as argument
set -o allexport
source $1
set +o allexport

# create a new repository
restic -r s3:${S3_ENDPOINT} init