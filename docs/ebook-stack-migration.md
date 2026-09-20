# Ebook migration to skepsis

Approved 2026-09-20. Ordinary QM book requests mean EPUB plus audiobook; an explicit format request overrides that default. Reading history, old requests, and retired application settings can be discarded.

## Layout and ownership

- Storyteller is the reading/listening interface for iPhone, iPad, and browsers.
- BookOrbit owns library organization and metadata.
- Shelfmark supplies direct ebook sources; BookOrbit supplies torrent requests through the existing Prowlarr.
- A separate Mullvad device, Gluetun, qBittorrent, and Mousehole serve books on skepsis.
- QM coordinates the two formats, tracks missing files, and submits matching pairs to Storyteller for alignment.
- The shared Prowlarr, Sonarr, Radarr, existing Gluetun, and existing qBittorrent remain on chrysaora.

Files live under `~/selfhosted/data/books` on skepsis: `library/ebooks`, `library/audiobooks`, `incoming`, and `downloads`. Application state lives in the usual `data/<app>` directories. Torrent payloads remain separate from editable library copies so metadata edits cannot invalidate seeding.

## Work order

1. Stop the failed legacy MAM updater and unused ebook automation.
2. Copy and hash-verify ebooks, audiobooks, and Storyteller assets. Recover useful BookLore metadata before deleting its database.
3. Deploy BookOrbit and Storyteller with bounded CPU/memory use. Verify imports, synced editions, authentication, and Caddy routes.
4. Prepare the separate download stack. Enable it only after its own Mullvad device and valid MAM session are available.
5. Add QM paired requests, acquisition status, and sequential Storyteller processing. Validate with existing owned files before acquiring anything new.
6. Remove retired containers and their data, archive their app definitions, and remove obsolete routes and credentials. Preserve the existing MAM torrent until its seeding obligations and transfer are settled.

## Constraints

Do not modify Embral. Only reload Caddy after validation; never restart Docker or the shared movie/TV VPN stack. Preserve unrelated repository changes. Commit locally on main; do not push.

EPUB files normally preserve title, author, identifiers, and other embedded metadata. Database-only edits, collections, and covers are not guaranteed to be embedded. Original audiobook files and Storyteller's generated synced EPUBs must also be retained.

The existing MAM torrent reports an account that is parked, and the old updater reports an invalid session. No new MAM searches, downloads, or seedbox-session updates should run until the account is restored and its session is configured. Never reuse the active movie/TV Mullvad WireGuard device concurrently on skepsis.

## Retirement authorized

Readarr/Bookshelf, BookLore and MariaDB, seedboxapi, stopped Audiobookshelf, and old Shelfmark/Ephemera installations and data on chrysaora. Book files must be verified on skepsis before their old copies are removed. No retention of retired application databases or user history is required.
