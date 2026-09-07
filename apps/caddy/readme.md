### Reloading the Caddyfile

Run `./reload-caddyfile.sh --check` to validate the host's `Caddyfile`, then
`./reload-caddyfile.sh` to validate and reload it without restarting Caddy.
The script works from any working directory.

The script copies the host file into the container before validation. Docker's
single-file bind mount can retain an old inode after an editor replaces the host
file, so reloading `/etc/caddy/Caddyfile` directly may silently reload stale
configuration. The temporary copy is removed after use. A failed validation
leaves the active configuration unchanged.

### Forward auth

Import the snippet `fa_authentik` into the compose files of other services to enable forward auth.
```yaml
labels:
    caddy.import: fa_authentik "<matcher if needed, otherwise `*`>"
```

In Authentik's admin panel, create a `Proxy Provider`, of type `Forward auth (single application)`. The external host should match the domain of the service, with an `https://` scheme pre-pended. Next, create an application using that provider. Finally, go to the Authentik embedded outpost and add the new application to the selected applications.
