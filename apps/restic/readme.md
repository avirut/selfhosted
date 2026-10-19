# Backups

```sh
./backup.sh                              # Back up apps now
./list-snapshots.sh                      # List this host's snapshots
./list-snapshots.sh --host all --latest 1 # Latest snapshots across all hosts
./remove-old.sh                          # Preview retention
./remove-old.sh --apply                  # Apply retention
```

Use `--help` for options. `backup.sh embral` selects the separate Embral set;
`list-snapshots.sh --profile apps` filters to apps. Commands request sudo when
needed. Credentials stay in `/etc/kroacnet-backup`.

The scripts call `/opt/kroacnet-backup/backup_cli.py`, which uses the existing
backup and maintenance services. Keep the existing systemd timers; no cron setup
is needed. Maintenance retains the configured policy and freshness checks.

Backups contain a prepared on-disk copy under `/var/lib/kroacnet-backup`, including
selected source files, consistent database exports and client snapshots. This is
not a symlink to live application data. Restic compresses and deduplicates it.
