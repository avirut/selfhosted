#!/bin/bash

python3 convert_hostmap_to_caddy.py > ./caddy-ingress.json
docker exec caddy-ingress caddy reload --config /etc/caddy/caddy-ingress.json