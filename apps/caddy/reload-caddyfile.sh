#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# An editor can replace the host file's inode while Docker's single-file bind
# mount still points to the old inode. Always load a fresh copy from the host.
container_config="$(docker exec caddy mktemp /etc/caddy/Caddyfile.reload.XXXXXX)"
trap 'docker exec caddy rm -f -- "$container_config" >/dev/null' EXIT
docker cp "$script_dir/Caddyfile" "caddy:$container_config" >/dev/null

docker exec -w /etc/caddy caddy caddy validate --config "$container_config" --adapter caddyfile
if [[ "${1:-}" != "--check" ]]; then
    docker exec -w /etc/caddy caddy caddy reload --config "$container_config" --adapter caddyfile
fi
