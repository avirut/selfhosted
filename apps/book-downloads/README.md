# Book downloads on skepsis

This stack is separate from the movie/TV VPN on chrysaora. Never copy its active WireGuard key here.

Private `.env` contains `WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES`, a single `SERVER_HOSTNAMES`, `MOUSEHOLE_AUTH_PASSWORD`, and `MOUSEHOLE_AUTH_TOKEN`. Obtain the first three from a separate Mullvad device. Secrets and application state are excluded from Git.

Start Gluetun, Mousehole, and Shelfmark with `docker compose up -d`. qBittorrent requires the explicit `torrents` profile. Do not enable that profile until the MAM account is unparked, the session is valid, and outstanding seeding obligations have been checked.

Mousehole is available through an SSH tunnel to skepsis port 5010. Create a dedicated MAM API session using the VPN IP Mousehole reports, **ASN** locking, and **Allow Session to set Dynamic Seedbox: Yes**. Prowlarr needs its own session for its own outgoing IP. See the [upstream instructions](https://github.com/t-mart/mousehole/blob/v0.5.0/docs/getting-your-cookie.md).

Mousehole's cookie and rotated session state persist under `data/book-downloads/mousehole`. Its normal five-minute schedule handles updates; do not repeatedly press Update Now. MAM limits IP changes to once an hour across the account. Keep the selected VPN server fixed and resolve any new ASN before changing servers.

The qBittorrent entrypoint waits for a fresh successful Mousehole response matching Gluetun's current public IP before starting. This also runs after a daemon restart and can wait up to five minutes for Mousehole’s next scheduled contact. A missing/invalid cookie or an update cooldown leaves it waiting. This is a startup check, not continuous monitoring: stop book qBittorrent before deliberately changing VPN servers. VPN recovery, session rejection, and restart behavior must be tested before unattended MAM downloading is enabled.

Recreate this whole Compose project together when changing Gluetun configuration. Recreating only Gluetun can leave other containers attached to its old network namespace. Never run this project's commands in `apps/arr`.

BookOrbit uses `http://books-gluetun:8080` for qBittorrent and `/books/downloads` for completed files. Library imports must copy torrent payloads; editing a hardlinked EPUB can invalidate seeding. Shelfmark writes direct downloads into BookOrbit's `/books/incoming` Book Dock. No torrent access is configured in Shelfmark.

The existing MAM torrent is paused on chrysaora. Its exported torrent and verification manifest are private under `data/book-downloads/mam-transfer`; its payload was copied and SHA-256 verified at `/books/downloads/mam-transfer` on skepsis. Import it stopped, recheck all pieces locally, then start only after the new session is valid. Remove its old torrent and payload only after successful tracker registration and the account’s seeding obligations are confirmed.
