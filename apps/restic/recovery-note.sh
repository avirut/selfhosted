#!/usr/bin/env bash
# Owner-run terminal output for the independent vault; never paste into Git/chat.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: sudo recovery-note.sh /etc/kroacnet-backup/selfhosted.env' >&2; exit 2; }
printf '%s\n' '# Shared Restic credentials. Install Restic; clone avirut/selfhosted.'
printf '%s\n' '# Save these assignments as a private env file, then run apps/restic/list-snapshots.sh ENV.'
cat -- "$1"
