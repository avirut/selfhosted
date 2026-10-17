ARG CADDY_VERSION=2.11.7

FROM caddy:${CADDY_VERSION}-builder AS builder

RUN xcaddy build \
        --with github.com/caddy-dns/cloudflare@v0.2.4 \
        --with github.com/mholt/caddy-dynamicdns@67d107a42c02

FROM caddy:${CADDY_VERSION}-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
