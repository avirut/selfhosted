# Paseo Hub

Skepsis deployment for kroacnet issue #10. Based on the upstream
[Compose stack](https://github.com/getpaseo/hub/blob/main/compose.yml) and
[self-hosting guide](https://paseo.sh/docs/hub/self-hosting), checked October 17,
2026. The Hub image is pinned to the pulled digest; upgrades are deliberate.

Copy `.env.example` to `.env`, choose the public origin and a random database
password, and keep that file mode 0600. Run `docker compose config --quiet`,
then `docker compose up -d --wait`. No host ports are published. Caddy reaches
`paseo-hub:3000` on the existing `swarmnet`; PostgreSQL is on an internal network.

The private Caddy snippet and Authentik application restrict the dashboard to
the owner. Exact CLI login/poll/enrollment and daemon WebSocket routes use Hub
native device/bearer authentication so headless daemons can connect; they do not
accept a client-supplied owner header. Adapt `paseo-hub.caddy.example`, create a matching single-application
forward-auth provider bound only to the owner, and add it to the existing
embedded outpost before importing the snippet. Hub's first-operator setup and application/daemon connections are
separate from deploying this stack. No workflow, trigger or recurring task is
created by Compose. Browser setup is permitted only through the protected site.

PostgreSQL state is under `~/selfhosted/data/paseo-hub/postgres`; the private
`.env` contains the database password. Review backup coverage before claiming
recovery. Before upgrades, take a PostgreSQL dump: upstream migrations are
forward-only, so recovery may require the matching database backup and image.
Do not run `down -v` or remove the state directory during normal maintenance.

LibreChat was retired October 17 after explicit owner approval to delete its
containers, original data and local recovery archive. No conversations were
imported into Hub. Historical cloud snapshots expire under normal retention.
