# Paseo web UI

Serve the installed Skepsis daemon's bundled browser client through the existing
Caddy/Authentik deployment. No second daemon or frontend build is needed.
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

Adapt the Caddy example with the hostname and owner username, create a matching
Authentik forward-auth application bound only to the owner, and import the
snippet. Every web/API/WebSocket request goes through owner authentication.
Caddy forwards the public Host and HTTPS scheme; the daemon emits the matching
secure browser connection hint. Verify the UI and WebSocket, not just the HTML.

Other machines are added through the web client's normal Add Host/pairing flow.
Pairing offers are credentials: never put them in this repository or a shared
page. Browser pairing state belongs to that browser origin.

Disable the socket and its service and remove the Caddy import to withdraw this
web entrypoint. This does not stop the existing daemon or its agents. Hub is a
separate application and hostname; see `../paseo-hub`.
