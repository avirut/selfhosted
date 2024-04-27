ARG CADDY_VERSION=2.7.6

FROM caddy:${CADDY_VERSION}-builder AS builder

RUN xcaddy build \
        --with github.com/caddy-dns/cloudflare \
        --with github.com/mholt/caddy-dynamicdns@f375a72

FROM caddy:${CADDY_VERSION}-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
