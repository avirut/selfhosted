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

The existing MAM torrent reports an account that is parked, and the old updater reports an invalid session. No new MAM searches, downloads, or seedbox-session updates should run until the account is restored and its session is configured. Never reuse the active movie/TV Mullvad WireGuard device concurrently on skepsis.

## Retirement authorized

Readarr/Bookshelf, BookLore and MariaDB, seedboxapi, stopped Audiobookshelf, and old Shelfmark/Ephemera installations and data on chrysaora. Book files must be verified on skepsis before their old copies are removed. No retention of retired application databases or user history is required.


## Deployed status (2026-09-20)

- BookOrbit 2.10.0 and PostgreSQL/pgvector 18 are running on skepsis. `https://books.kroac.net` serves BookOrbit; the setup endpoint is closed after owner creation. The private owner credential is in `data/bookorbit/admin.json` (0600); Shelfmark and book qBittorrent use that same owner login. Existing Storyteller logins remain valid.
- Storyteller web-v2.14.21 serves its existing public hostname. The five previous aligned books survived the upgrade; authenticated partial downloads and every SMIL audio reference were verified. No missing resources were found.
- 271 EPUBs (774,236,085 bytes before metadata write-back), seven M4Bs (4,873,005,019 bytes), and 417 Storyteller files (4,865,609,179 bytes) were copied and SHA-256 verified before source deletion. All EPUB archives passed CRC checks. All 271 active BookLore records were imported; their titles were verified in the resulting EPUB metadata. The one deleted BookLore record was omitted.
- BookOrbit watches the ebook and audiobook folders. EPUB metadata write-back is enabled. Its Book Dock is configured for metadata lookup and automatic filing at confidence 90, with uncertain files held for review. Native request import verification is also 90. Automatic grabs/searches remain off.
- MAM and TorrentLeech Torznab connections point to the existing Prowlarr and are saved **disabled**. The qBittorrent API configuration cannot be saved until the new VPN container's hostname resolves. Its intended client settings are category `bookorbit`, hardlinks off, and identical `/books/downloads` paths in both containers.
- The separate book download Compose project is prepared with Gluetun v3.41.3, qBittorrent 5.2.0, Mousehole 0.5.0, and Shelfmark v1.3.15. Shelfmark and qBittorrent authentication/configuration were checked in temporary containers with networking disabled; those test containers were removed. DHT/PEX/LSD are disabled, seeding limits are unlimited, and qBittorrent is bound to `tun0`.
- qBittorrent's startup gate passed seven isolated cases, including stale state, wrong IP, missing/rejected cookies, and MAM rate limiting. These tests made no MAM requests. Real VPN recovery and restart tests remain required before enabling downloads.
- QM has paired requests, ownership checks, retry protection, library status, isolated file staging, and Storyteller import/alignment commands. Its ten-minute user timer is installed and verified. All 271 EPUBs are now in Storyteller. Four packaging problems were repaired without changing reading text: three OPF namespace representations and one malformed Gatsby cover page/reference. The existing Elantris pair was reused live. The two previously unaligned Cixin Liu pairs are processing sequentially after correcting author-name metadata. No new book download was submitted.
- QM's Shelfmark commands search direct sources, let the conversational agent select a returned EPUB release, submit it once, and associate the imported ebook with its native request. Simulated tests cover authentication, duplicate submissions, uncertain responses, and refusal to alter requests with tracker attempts. Acquisition is still disabled. BookOrbit auto-grab must stay off for this path because its native fulfillment endpoint can remove associated torrents; audio releases can be selected through its API/UI.
- Final verification: both public routes respond, Storyteller reports 271 present ebooks and seven present audiobooks with no missing assets, the QM sync timer completes successfully, and QM's suite passes 75 tests with five skipped. Type checking reports no errors or warnings.
- BookLore/MariaDB, Readarr, seedboxapi, old Shelfmark, Audiobookshelf, and old Storyteller containers were removed from chrysaora. Their obsolete data and the migrated media source copies were deleted. Old application definitions are archived. Retired image tags were removed without global pruning.
- The old MAM torrent is paused and its payload remains in the original qBittorrent pending seeding-account review. Pausing prevents it from announcing from the old VPN IP during the later session transfer. All 83 existing torrents and the movie/TV services remain on chrysaora. Its pre-existing unstaged WireGuard-address change was preserved. No Embral files or containers were modified. Only ebook Caddy routes changed, followed by validation and reload.

## Remaining activation work

1. Save a separate Mullvad device's configuration at `data/book-downloads/mullvad.conf`; configure its key, address, and selected server in `apps/book-downloads/.env`, then delete the intermediate file.
2. Unpark MAM and check seeding obligations. Start the new VPN and Mousehole, create a dedicated ASN-locked dynamic-seedbox session for their reported IP, and keep it separate from Prowlarr's session. Resolve the existing seeded torrent before retiring its old copy.
3. Check tunnel binding, kill switch, restart order, session persistence, and VPN recovery. Start the torrent profile only after those prerequisites; configure and enable the BookOrbit client and sources deliberately.
4. Start Shelfmark, add its Caddy route with native login, enable QM's `SHELFMARK_ENABLED` flag, and verify a direct-source import and native request association. Keep BookOrbit auto-grab off while using this path. Verify a selected audio torrent through BookOrbit after MAM is ready.
5. Verify new alignment results on iPhone/iPad and in the browser. CPU processing is sequential with two CPUs and 4 GiB maximum memory. Alignment status alone is not a quality guarantee.
6. User lingering is still disabled on skepsis. The existing pending `loginctl enable-linger avirut` step also affects the new QM user timer's operation without an active login.
