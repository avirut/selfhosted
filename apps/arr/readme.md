# Movie and TV services on chrysaora

Sonarr and Radarr own the libraries, monitoring, release selection and imports.
Prowlarr manages their indexers. qBittorrent downloads through Gluetun; Real-Debrid
and rdtclient are no longer part of the active path. qm uses the supported
Sonarr/Radarr APIs, including its owner and delegated iMessage commands. SABnzbd
remains configured; current indexers use torrents.

The external disk is mounted at `/mnt/data`, with `media/movies`, `media/tv`,
`torrents/movies` and `torrents/tv`. Preserve these paths and the existing profiles
and custom formats. Do not adopt larger TRaSH-recommended size limits by default;
normal file sizes and H.265 are preferred where the configured profile allows.

## Updates

On 2026-09-20, updated and pinned Sonarr 4.0.20.3014, Radarr 6.4.4.10685 and
Prowlarr 2.6.5.5623. Each application was stopped before archiving its complete
configuration directory. Backups, private Compose/environment copies, API
snapshots and old image references are in
`~/.local/state/qm/backups/apps-20260920/` on chrysaora. Archive integrity was
checked before starting the new containers.

The 61-series and 206-movie libraries retained their IDs. Download-client values
were unchanged. qm's media and books checks passed, including the shared Prowlarr
integration. qBittorrent and Gluetun ran uninterrupted during these updates.

Use `docker compose up -d --no-deps SERVICE` to update only the intended service
after its backup. Preserve the live host's private VPN configuration; chrysaora's
existing WireGuard address differs from this checkout's historical committed
value. Do not overwrite its Compose file wholesale from another machine.
Do not restart the Docker daemon or shared network.

For rollback after an application migration, stop that application and restore
its configuration directory together with its old image. Retain the failed
state separately for inspection; do not downgrade an image against migrated data.

Pre-existing health warnings remain for the kickasstorrents.ws, Magnet Cat and
LST indexers, and for Prowlarr's retired Readarr connection. No tracker sessions,
indexer definitions, download-client settings or VPN settings were changed by
this upgrade.
