# BookOrbit

BookOrbit runs on skepsis at https://books.kroac.net, with its own PostgreSQL/pgvector container. Library files live under `data/books/library`; torrent payloads and Book Dock incoming files have separate directories under `data/books`.

## Authentik

Native OpenID Connect is enabled and the owner confirmed a successful login on 2026-09-20. The [Authentik blueprint](authentik.yaml) creates only BookOrbit's provider, application, and owner-only policy binding. It does not change the shared outpost or another application's access policy.

BookOrbit's provider settings are:

- Slug/name: `authentik` / `Authentik`.
- Issuer: `https://auth.kroac.net/application/o/bookorbit/`.
- Client ID: `bookorbit`; confidential client secret stored in each application's database.
- Callback: `https://books.kroac.net/oauth2-callback` (strict match).
- Scopes: `openid profile email`; username claim `preferred_username`.
- Link an existing local username: enabled. Automatic creation of users: disabled.

The Authentik policy allows only `avirut`, whose first SSO login links to the existing BookOrbit owner account. Local API authentication remains enabled for QM. Private owner credentials are in `data/bookorbit/admin.json`; never commit them.

To recreate the provider, apply the blueprint through `ak apply_blueprint` with `BOOKORBIT_OIDC_CLIENT_SECRET` available to that command, then configure the same secret through BookOrbit's supported settings API/UI. Remove the one-time blueprint from the running container afterward so it cannot reapply stale settings. Back up Authentik before changing its configuration.

See the [migration report](../../docs/ebook-stack-migration.md) for request routing, MAM precautions, and activation status. Metadata edits write back to library EPUBs; existing Storyteller copies need their own display-metadata updates.
