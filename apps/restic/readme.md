# Restic backups

Install Restic, clone this repository and copy `.env.example` to a private env
file. Fill in the shared repository URL/password and storage key. Keep it outside
Git (`chmod 600 selfhosted.env`). These commands work on a fresh machine:

```sh
./list-snapshots.sh selfhosted.env
./list-snapshots.sh selfhosted.env --host sophon-media --tag apps --latest 1
./restore.sh selfhosted.env SNAPSHOT_ID --target ./recovered --verify
./backup.sh selfhosted.env /path/to/prepared/files --host HOST --tag apps
./remove-old.sh selfhosted.env --dry-run
```

All scripts directly call Restic. `common.sh` only loads the env file. Listing
shows every device by default; there is one shared repository and password.
`remove-old.sh` keeps all points from the latest48hours plus14 daily,8 weekly,12 monthly and3 yearly points,
grouped independently by host and tag. Add `--prune` to reclaim unreferenced data.
Only Skepsis schedules repository maintenance. Snapshots share unchanged content
across devices; different paths and hosts still share identical content chunks.

## Scheduled preparation

`run-backup.sh ENV HOST_CONFIG PROFILE` acquires the local operation lock, calls
`prepare.sh`, and invokes the same `backup.sh` above. Preparation selects the
reviewed sources in `hosts/`, writes PostgreSQL dumps using the installed database
container's tools, replaces SQLite files with online CLI backups, and records
file hashes under `/var/lib/kroacnet-backup/PROFILE/payload`. It excludes live WAL
sidecars, caches, downloaded media and models. Mac/Windows are independent daily
writers; their snapshots are not coupled to Skepsis's apps job.

Preparation uses standard Bash, rsync, sqlite3, jq and shasum. Linux uses timeout;
Mac uses a bounded child process with its installed Bash. Linux services run protected installed script copies; root timers never
execute a user-writable checkout. macOS uses a launchd job as the source owner;
Windows uses native PowerShell, CLI sqlite3/Restic and Task Scheduler. Source
credentials and private client settings are not part of this repository.

Linux apps schedules: Skepsis03:30, VM10003:50, VM10104:10, Sophon04:30;
Embral03:10 daily. All times America/Chicago. Native client times are documented
with their installed job definitions. Weekly maintenance on Skepsis is Sunday
05:30; clients use Restic's repository lock retry when maintenance is active.
Freshness monitoring uses the shared catalogue and the existing QM owner outbox.
Monthly verify.sh restores small settings/SQLite samples from every host and set;
this is a bounded recovery check, not a full application rebuild. PostgreSQL
restore acceptance uses an isolated matching-version server during migration.

Stages are separate on-disk copies. They provide consistent database exports,
not a global atomic transaction across applications. A failed preparation cannot
upload a prior stage. JSONL copies retain complete records and fail on detected
rewrite/truncation. Gaming saves configured as stable fail if changed during copy.

## Restoring applications

Restore into an empty private directory. No running host, timer or Python helper
is needed to list or retrieve files. Select a snapshot ID explicitly: unfiltered
`latest` only selects one host/set. The restored `files/` tree preserves original
absolute paths below it, and `databases/CONTAINER/` holds globals and custom-format
PostgreSQL dumps. `SHA256SUMS` checks staged content (`shasum -a 256 -c SHA256SUMS`).
SQLite files are completed standalone online snapshots; verify with
`sqlite3 FILE 'PRAGMA integrity_check;'`.

Database imports require their normal application tools. Stop the affected app,
restore settings/files, then import PostgreSQL globals and dumps into a matching
server major version. Restore SQLite files while their app is stopped. Review
queued actions and device identities before starting workers or restored daemons.
File-backed tokens may expire; Mac Keychain and Windows DPAPI state may require
normal sign-in or re-pairing on replacement hardware. Browser calibration and
microphone/output preferences are intentionally excluded. Bulk media is excluded.

Keep the env credentials and this recovery procedure available in the owner's
independent vault. Credentials found only inside their encrypted backup cannot
bootstrap recovery. The shared storage key allows access to the shared repository;
normal repository password protection does not provide deletion protection.

## Installing schedules on Linux

Install standard packages (Restic, sqlite3, rsync, jq, coreutils, util-linux and
shasum), review the matching hosts/HOST.sh source selection, then run:

```sh
sudo ./install-linux.sh skepsis /private/path/selfhosted.env
sudo systemctl start restic-backup@apps.service
sudo systemctl enable --now restic-apps.timer
```

Use sophon-media, sophon-gpu or sophon for those hosts. Only Skepsis enables
restic-embral.timer, restic-monitor.timer, restic-maintenance.timer and
restic-verify.timer. Shared maintenance waits for all seven sets to be fresh and
for successful restore verification within40days. Never automatically unlock a
repository. Host mounts and forbidden-root checks must pass before preparation.

On Mac, reviewed hosts/ambrosia.sh plus macos/launcher/plist use the source owner
and native launchd; on Windows, windows/ scripts and task XML use PowerShell5.1,
official Restic/SQLite executables and a private56-source JSON allowlist. The
Windows native allowlist is settings data; no Python installation is needed.
The native producer removes its private pending payload after confirmed upload.

Windows source repositories are stored as `ALIAS/worktree/` plus `ALIAS/git/`.
The latter contains a Git bundle of refs/history (including reflog history),
an additional pack of staged objects, exact index/control files and recovery
metadata. Background fetch bookkeeping can change without invalidating a backup;
local refs, index, HEAD and selected working files must stay stable. This keeps
unpublished branches, stashes, staged changes and untracked source recoverable.

For source recovery, verify the enclosing manifest and initialize an **empty**
repository with the recorded object format. Verify/unbundle `history.bundle`,
restore its refs and the recorded local symbolic refs, copy `index-objects-*`
into `.git/objects/pack/` as `pack-*`, then copy `git/control/` into `.git/` and
`worktree/` into the empty working tree. Do not check out HEAD first: that would
resurrect intentionally deleted working files. Inspect restored config/hooks
before using them; disable hooks/fsmonitor during validation. The complete
procedure is in `windows/windows-git.ps1`. Validate with `git fsck`, status and
the staged diff. No original source host or backup runtime is required.

Skepsis owner terminal export for the vault is recovery-note.sh ENV. Its output
contains secrets: save it independently and never put it in Git or a chat. It
only reads the existing single env; it does not create credentials or contact B2.
