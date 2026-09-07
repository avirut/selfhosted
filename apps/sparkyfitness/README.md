# SparkyFitness

Personal nutrition, exercise, and body-measurement store at
https://sparky.kroac.net. Both application images are pinned to v1.6.4 and use a
dedicated PostgreSQL 18 database.

Run commands from this directory:

```sh
docker compose config --quiet
docker compose up -d --wait
docker compose ps
```

All three services use the existing external `swarmnet`, following this host's
other stacks. Caddy connects to `sparkyfitness:80`; its nginx serves the UI and
proxies `/api` and `/mcp` to `sparkyfitness-server:3010`. No host ports are
published. The frontend health check also checks its connection to the API.
The frontend's `depends_on.restart` refreshes nginx's backend DNS resolution
when Compose explicitly updates/restarts the server. If recreating the backend
outside Compose, recreate or restart only this frontend afterward as well.

`.env.template` documents configuration. The live `.env` and `.credentials.env`
are ignored by Git and have mode `0600`. The latter holds the owner login
(`avirut@kroac.net`), generated password, and API key. The account was created
through the normal signup API, granted admin access by the configured admin
email, and then signup was disabled before public access. Developer tools are
disabled. Ordinary operation does not require an AI-provider API key.

The MCP endpoint is `https://sparky.kroac.net/mcp`, using Streamable HTTP with
`Authorization: Bearer <API_KEY>`. The key was created through the application's
supported API and has the application's default one-year lifetime. Manage or
renew it through Settings / API Key Management. Native MCP client registration
is separate; the endpoint is also accessible directly from scripts. Use the
normal food, exercise, and check-in tools; do not edit the application database.

Durable data lives under `~/selfhosted/data/sparkyfitness/`: `postgresql/`,
`uploads/`, and `backup/`. The database mount targets `/var/lib/postgresql` for
PostgreSQL 18. Its host directory must belong to the image's `postgres` user;
an empty directory owned by the host user with mode `0700` is not sufficient.
The current directory was initialized with the correct ownership.

Back up the database using `pg_dump`, retain uploads and private configuration,
and keep the API encryption key and `BETTER_AUTH_SECRET` unchanged across
upgrades. For example:

```sh
docker compose exec -T sparkyfitness-db pg_dump -U sparky -d sparkyfitness -Fc > /path/to/private-backup/sparkyfitness.dump
```

Choose explicit versions and back up before upgrading both application images
together. The server owns its migrations and restricted application database
role. `docker compose stop` preserves all data.

Apple Health requires the iOS companion app and Health permissions. Withings
requires OAuth application credentials and account authorization. Those device
integrations and the Tandoor recipe provider have not been configured yet; no
external accounts were connected during deployment.

Upstream deployment reference: [released Compose example](https://github.com/CodeWithCJ/SparkyFitness/blob/v1.6.4/docker/docker-compose.prod.yml).
