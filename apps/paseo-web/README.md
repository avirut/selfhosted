# Paseo web UI

Serve a checked copy of the installed daemon's browser client through the existing
Caddy/Authentik deployment, with centrally configured hosts loaded before startup.
No second daemon, frontend fork or build toolchain is needed. The installed
package and its JavaScript bundle are not modified.
[Upstream instructions](https://paseo.sh/docs/web-ui), checked October 17, 2026.

Enable `features.webUi.enabled` in the existing daemon and allow the public
hostname in `daemon.hostnames`, preserving other settings. Run `paseo reload`
and use the supported worker restart if it reports the web UI setting requires
one. The daemon stays on `127.0.0.1:6767`; existing relay access stays enabled.

Install the two user units from this directory into `~/.config/systemd/user`,
reload systemd, then enable/start `paseo-web.socket`. The socket is mode 0600
under `~/selfhosted/data/caddy/config`, already mounted into Caddy as `/config`.
The socket-activated systemd proxy forwards to the localhost daemon. It opens
no new TCP listener and adds no daemon or provider credentials.

Adapt the Caddy example with the hostname and owner username and a matching
Authentik forward-auth application bound only to the owner. Every static file,
private host configuration, API and WebSocket request goes through owner
authentication. API/WebSocket paths still proxy to the existing private socket;
the prepared client is served from `/config/paseo-web-ui/current`. Responses use
`private, no-store`, including compressed static files and the host configuration.

## Configured hosts

Keep the actual configuration in an owner-only file outside Git, for example
`~/.config/kroacnet/paseo-web/hosts.json` (directory 0700, file 0600). Its shape is
`{ "version": 1, "hosts": [{ "name": "HOST_LABEL", "offer": CONNECTION_OFFER }] }`.
An offer is the decoded version-2 fragment from the daemon's supported
`paseo daemon pair --json` command, with its server ID, public key and TLS relay
endpoint. Retrieve/validate it privately; never paste real offers into this repo.

`bootstrap.mjs` fetches the configuration after owner sign-in, updates Paseo's
browser registry, then loads the unchanged upstream bundle. New browser profiles
receive every configured host. Existing passwords, appearance, alternate
connections and unrelated hosts are retained; configured labels and relay
identities come from the central file. Offline hosts do not block startup.
Removing a previously managed host from the configuration removes that browser
entry on the next load. This does not revoke a pairing held by another client.
Browser client identities/private keys are never shared. Local additions remain
local; this is not bidirectional settings synchronization.

If the configuration is unavailable or invalid, startup stops with a short Retry
message and does not erase the saved registry. There is no unauthenticated
configuration route or public pairing page.

## Prepare and deploy

```sh
node --test apps/paseo-web/managed-hosts.test.mjs
python3 apps/paseo-web/prepare.py \
  --upstream /path/to/installed/server/dist/server/web-ui \
  --hosts "$HOME/.config/kroacnet/paseo-web/hosts.json" \
  --output "$HOME/selfhosted/data/caddy/config/paseo-web-ui/releases/RELEASE"
```

The output must be new. It contains the upstream assets, a changed HTML
entrypoint, the loader and a private configuration copy. Obsolete compressed
upstream HTML is removed so it cannot bypass the loader. The app assets remain
byte-identical. The preparation checks `compatibility.json` against the exact
installed bundle hash; an unknown upgrade fails before creating output.

Test the prepared release with `browser-test.mjs` using Playwright Core and
Chromium. It opens a temporary loopback server, uses two empty isolated browser
contexts, and checks real daemon connections, distinct browser identities and
configuration failure/recovery. Set `PLAYWRIGHT_MODULE` and `CHROMIUM_PATH` to
the test runtime. It reports only host labels/status, never offers or chat data.

After verification, atomically point the relative `current` symlink at
`releases/RELEASE`, preserving the previous target for rollback. Install the
adapted Caddy snippet and validate/reload using the existing Caddy helper. No
daemon restart is needed for host-list or prepared-client changes. Check public
unauthenticated requests to both the page and `/_kroacnet/hosts.json` redirect
to Authentik even when supplying a forged owner header.

On a Paseo upgrade, review the registry schema and HTML entrypoint, update the
compatibility record, and repeat the tests before switching to its prepared
release. Roll back by restoring the previous symlink target and Caddy snippet;
do not overwrite installed package files or browser private identity keys.

Disable the socket and its service and remove the Caddy import to withdraw this
web entrypoint. This does not stop the existing daemon or its agents. Hub is a
separate application and hostname; see `../paseo-hub`.
