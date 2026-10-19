# Restic operator scripts

These scripts use the current, root-installed backup system. Credentials stay in
`/etc/kroacnet-backup`; no credentials are copied into this repository.
The reviewed operator helper must be installed at `/opt/kroacnet-backup/backup_cli.py`.
Commands work from any working directory and ask for sudo when needed.

```sh
./backup.sh                       # Run the existing local apps backup and wait
./list-snapshots.sh               # Current local repository, all profiles
./list-snapshots.sh apps --latest 1
./list-snapshots.sh all --latest 1 # All current host repositories, via recovery configs
./list-snapshots.sh --json         # Machine-readable current snapshots
./remove-old.sh                   # Preview local retention; delete nothing
./remove-old.sh --apply           # Run existing guarded local maintenance and wait
```

`backup.sh embral` selects that separately configured profile on hosts that have
it. Normal apps backup includes configured remote client exports. Snapshot sizes
are logical file sizes, not additional uploaded bytes or billed storage.

For compatibility, the exact argument `selfhosted.env` selects current apps in
`backup.sh` and `list-snapshots.sh`, and current local retention in `remove-old.sh`.
It **does not load the old env file**. Other env filenames are not accepted for
current backup or cleanup operations. To inspect old snapshots explicitly:

```sh
./list-snapshots.sh --legacy selfhosted.env
```

The retained env is trusted shell code containing legacy credentials; keep it
private. Legacy listing is the only legacy operation in these three scripts.
No legacy snapshots are removed by current maintenance. `create-repo.sh`,
`recover.sh`, `.env.template` and `excludes.txt` belong to the historical setup;
do not use them to initialize or configure the current system.

## Existing automation

Keep the installed systemd timers. Do not add duplicate cron jobs. The scripts
can also be invoked by root noninteractively, but do not install user-writable
checkout scripts as new privileged scheduled commands. Scheduled jobs already use
reviewed root-owned helpers and service sandboxing.

Backup starts `kroacnet-backup@apps.service` (or the selected profile). Applying
retention starts `kroacnet-backup-maintenance.service`. Both retain the existing
operation lock, repository identity checks and failure handling. Preview and
maintenance require a fresh successful backup and recent restore verification.
Retention keeps 14 daily, 8 weekly, 12 monthly and 3 yearly points, with the
configured extra recent-history window where applicable. Maintenance includes
integrity checks and prune; it may take time and performs cloud reads.

Listing other hosts uses root-only recovery configurations on the physical host;
it does not start remote jobs. Cleanup only affects the local current repository.
No automatic unlock, repository creation, password copying or legacy deletion is
performed. If a command fails, inspect the installed backup status and service
journal; do not remove locks or bypass freshness checks.
