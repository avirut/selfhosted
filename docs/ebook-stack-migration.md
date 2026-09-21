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

Storyteller imports its own copies. Later BookOrbit metadata edits do not automatically update an already imported Storyteller edition. Correct metadata before importing where possible; use Storyteller's supported metadata editor/API for later display corrections. Replacing reading text or audio in an aligned edition can require reprocessing.

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

The owner restored MAM and confirmed no outstanding seeding/HnR warnings. Mousehole and Prowlarr now use separate working sessions. Never reuse the active movie/TV Mullvad WireGuard device concurrently on skepsis.

## Retirement authorized

Readarr/Bookshelf, BookLore and MariaDB, seedboxapi, stopped Audiobookshelf, and old Shelfmark/Ephemera installations and data on chrysaora. Book files must be verified on skepsis before their old copies are removed. No retention of retired application databases or user history is required.


## Deployed status (2026-09-20)

- BookOrbit 2.10.0 and PostgreSQL/pgvector 18 are running on skepsis. `https://books.kroac.net` serves BookOrbit; the setup endpoint is closed after owner creation. The private owner credential is in `data/bookorbit/admin.json` (0600); Shelfmark and book qBittorrent use that same owner login. Existing Storyteller logins remain valid. BookOrbit native OIDC is connected to Authentik, restricted to the owner, linked to the existing owner account, and confirmed working by the user. New-user provisioning is disabled.
- Storyteller web-v2.14.21 serves its existing public hostname. The five previous aligned books survived the upgrade; authenticated partial downloads and every SMIL audio reference were verified. No missing resources were found.
- 271 EPUBs (774,236,085 bytes before metadata write-back), seven M4Bs (4,873,005,019 bytes), and 417 Storyteller files (4,865,609,179 bytes) were copied and SHA-256 verified before source deletion. All EPUB archives passed CRC checks. All 271 active BookLore records were imported; their titles were verified in the resulting EPUB metadata. The one deleted BookLore record was omitted.
- BookOrbit watches the ebook and audiobook folders. EPUB metadata write-back is enabled. Its Book Dock is configured for metadata lookup and automatic filing at confidence 90, with uncertain files held for review. Native request import verification is also 90. Automatic grabs/searches remain off.
- MAM and TorrentLeech Torznab connections point to the existing Prowlarr, pass their tests, and are enabled. Prowlarr's failed MAM session was replaced for its public IP `68.251.135.169`. The qBittorrent API connection passes its test and is enabled, with category `bookorbit`, hardlinks off, and identical `/books/downloads` paths in both containers. Tracker ratio/time goals are not imposed.
- The separate book download Compose project is active with Gluetun v3.41.3, qBittorrent 5.1.4, Mousehole 0.5.0, and Shelfmark v1.3.15. BookOrbit 2.10 does not recognize qBittorrent 5.2's new login cookie, so the compatible client version is pinned. MAM rejects port 6881; the fixed torrent port is 51413. DHT/PEX/LSD/UPnP are disabled, seeding limits are unlimited, and qBittorrent is bound to `tun0`. The dedicated Mullvad device uses fixed relay `us-dal-wg-001`, egress `146.70.211.120`.
- qBittorrent's startup gate passed seven isolated cases, including stale state, wrong IP, missing/rejected cookies, and MAM rate limiting. These tests made no MAM requests. The live kill switch blocked direct-IP traffic with the VPN stopped and recovered when restarted. Recreating the complete project retained Mousehole's cookie and kept qBittorrent waiting for a fresh successful scheduled contact. A later qBittorrent recreation retained its torrent and resumed seeding after the same gate.
- QM has paired requests, ownership checks, retry protection, library status, isolated file staging, and Storyteller import/alignment commands. Its ten-minute user timer is installed and verified. All 271 EPUBs are now in Storyteller. Four packaging problems were repaired without changing reading text: three OPF namespace representations and one malformed Gatsby cover page/reference. The existing Elantris pair was reused live. The two previously unaligned Cixin Liu pairs are processing sequentially after correcting author-name metadata.
- QM's Shelfmark commands search direct sources, let the conversational agent select a returned EPUB release, submit it once, and associate the imported ebook with its native request. Simulated tests cover authentication, duplicate submissions, uncertain responses, and refusal to alter requests with tracker attempts. The direct-source path passed a live EPUB download, restart recovery, metadata-preserving filing, native request association, Storyteller import, and authenticated download. Temporary test records/files were removed. BookOrbit auto-grab must stay off for this path because its native fulfillment endpoint can remove associated torrents; the conversational agent selects audio releases through its supported API. The timer reads Shelfmark's durable activity snapshot and files a known matching downloaded EPUB with its embedded edition metadata when a different provider edition scores below the general threshold.
- Final verification: all three public routes respond, Storyteller reports 271 present ebooks and seven present audiobooks with no missing assets, the QM sync timer completes successfully, and QM's suite passes 77 tests with five skipped. Type checking reports no errors or warnings.
- BookLore/MariaDB, Readarr, seedboxapi, old Shelfmark, Audiobookshelf, and old Storyteller containers were removed from chrysaora. Their obsolete data and the migrated media source copies were deleted. Old application definitions are archived. Retired image tags were removed without global pruning.
- The old Elantris MAM torrent was imported stopped, fully piece-checked, and registered successfully from skepsis. Its old torrent and payload were then removed; the other 82 torrents and movie/TV services remain on chrysaora. Temporary transfer exports were deleted after verification. Its pre-existing unstaged WireGuard-address change was preserved. No Embral files or containers were modified. Only ebook Caddy routes changed, followed by validation and reload.

## Remaining validation

User lingering is enabled (`Linger=yes`), and the ten-minute QM timer completes successfully without requiring an active login. All setup credentials have been supplied and activated.

The owner requested Stormlight Archive audiobooks as the first real acquisition test. All seven EPUBs already exist: The Way of Kings, Words of Radiance, Edgedancer, Oathbringer, Dawnshard, Rhythm of War, and Wind and Truth. Native audiobook requests 3–9 and paired QM deliveries reuse those EPUBs. Release searches succeed on MAM; Wind and Truth's complete editions require VIP, for which owner input is pending. Download/import and Storyteller attachment validation are in progress.

Alignment remains sequential with two CPUs and 4 GiB maximum memory. The Three-Body Problem is processing and Death’s End is queued ahead of new pairs. Verify synchronization on iPhone/iPad and in the browser after processing completes; status alone cannot guarantee alignment quality.
