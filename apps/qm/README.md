# qm web view

The application and Compose service live in `~/qm` to keep qm's code and runtime
configuration together. Caddy reaches the `web` service as `qm-web:3000` over the
existing `swarmnet`; there is no public host port. The grocery view is at
https://qm.kroac.net/groceries.

Authentik uses the qm application and a forward-auth proxy provider. The
[blueprint](authentik.yaml) records the application, provider, and owner-only
binding. It was applied through `ak apply_blueprint` on 2026-09-15. The new qm
provider is attached to the embedded outpost alongside its existing providers.
The app checks the trusted owner username as well. Back up Authentik before
changing access configuration.

To recreate the Authentik configuration, copy the blueprint under the server's
`/blueprints/` directory and apply its relative path with `ak apply_blueprint`.
Then add the resulting provider to the embedded outpost using Authentik's UI or
supported API/blueprint, preserving every current provider. The tracked blueprint
intentionally does not replace the shared outpost's provider list. Remove any
one-time deployment blueprint afterward so it cannot overwrite future changes.

```sh
cd ~/qm
docker compose up -d --build --no-deps --wait web
```

When changing Caddy, validate with `../caddy/reload-caddyfile.sh --check`, then
use that same script without `--check` to reload. Do not restart Caddy. Check
existing sites afterward. App deployment itself needs no Caddy reload.

Private `.env.web` and the complete domain/operation guide are in `~/qm`.
