# Grocy

Personal pantry and grocery-list store at https://grocy.kroac.net, using the
LinuxServer image pinned to Grocy 4.7.1.

Run commands from this directory:

```sh
docker compose config --quiet
docker compose up -d --wait
docker compose ps
```

Caddy connects to `grocy:80` on the existing external `swarmnet`. No host ports
are published. All application data, including SQLite, lives under
`~/selfhosted/data/grocy/config/` and belongs to UID/GID 1000.

`.env.template` documents the configuration. The live `.env` and
`.credentials.env` are ignored by Git and have mode `0600`. The latter holds the
`avirut` login name and API key. The owner manages the login password in the
application; no password copy is retained in this credential file. The initial `admin` account was
renamed and its default password replaced through the supported user API before
the site was published. Default `admin` / `admin` credentials no longer work.

The health check visits `/`, where Grocy runs its own database initialization and
migrations, then follows the login redirect. Visiting `/login` alone does not
initialize a fresh database.

Use the REST API with the `GROCY-API-KEY` header. `/api/stock` reads inventory;
stock addition, consumption, inventory correction, and undo have explicit
endpoints under `/api/stock/`. Product and shopping-list records use the documented
`/api/objects/` endpoints. The interactive API documentation is at `/api`.
Create or revoke keys through the application's API-key management page. Do not
edit its SQLite database for domain operations.

Batteries, equipment, and stock price tracking are enabled alongside pantry,
shopping, and locations. Recipes, chores, tasks, calendar, expiry, opened-product,
and freezing tracking remain disabled.
Maintain quantities as precisely as the available evidence reasonably supports;
qm normally summarizes those quantities as “have / low / out.” Preserve estimates
as estimates and reconcile them against later observations. Record receipt prices
per stock unit, with the store and purchase date, through the supported stock API.
See qm's food services guide for inventory and purchase-price conventions.

For a consistent full backup, stop only Grocy, archive its complete `config/`
directory and private credentials/configuration, then start it again. A live
database-only backup can use SQLite's backup interface, but does not include
uploads or configuration. Do not copy a live SQLite file as an ordinary backup.
Take a recoverable backup before changing the pinned image version; upgrades run
Grocy's own migrations. `docker compose stop` preserves all data.

Upstream deployment reference: [LinuxServer Grocy documentation](https://docs.linuxserver.io/images/docker-grocy/).
