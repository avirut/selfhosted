# Actual

Personal financial store at https://actual.kroac.net, pinned to 26.9.0.
Its data is in `~/selfhosted/data/actual`, mounted at `/data`. The service uses
`swarmnet`; Caddy reaches port 5006. Login uses the existing OIDC configuration.

The qm client in `/home/avirut/qm` pins `@actual-app/api` and `actualApiVersion`
to the same server version. Upgrade those together and run the money integration
tests and a live `npm run --silent money -- check` from qm before finishing an
upgrade. Ordinary verification must not trigger bank imports or ledger edits.

Updated on 2026-09-20 from 26.8.1. A complete stopped-state data archive, previous
Compose file and image reference are saved privately under
`~/.local/state/qm/backups/apps-20260920/`. The archive was checked before startup.
The existing OIDC session token, account/category counts, dated account reads and
August transaction reads worked with the upgraded client. Its 11 integration tests
and the qm type check passed.

For a future update, pull the intended image first, stop only `actual`, archive
the full data directory, update the pin, and start only this service. Preserve
the authentication configuration. For rollback after migrations, restore the
saved data together with its previous image; do not simply downgrade the image
against migrated data. Do not remove volumes or restart shared host services.
