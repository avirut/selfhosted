#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

container_config="$(docker exec caddy-edge mktemp /etc/caddy/Caddyfile.reload.XXXXXX)"
trap 'docker exec caddy-edge rm -f -- "$container_config" >/dev/null' EXIT
docker cp "$script_dir/Caddyfile" "caddy-edge:$container_config" >/dev/null

docker exec -w /etc/caddy caddy-edge caddy validate --config "$container_config" --adapter caddyfile
if [[ "${1:-}" != "--check" ]]; then
    docker exec -w /etc/caddy caddy-edge caddy reload --config "$container_config" --adapter caddyfile
fi
