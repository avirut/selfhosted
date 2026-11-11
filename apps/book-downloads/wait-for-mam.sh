#!/bin/sh
set -eu

started_at=$(date -u +%Y-%m-%dT%H:%M:%S)
echo "Waiting for Mousehole to confirm this VPN IP with MAM."
while :; do
    vpn_ip=$(curl --fail --silent --max-time 8 https://api.ipify.org || true)
    if [ -n "$vpn_ip" ] &&
        curl --fail --silent --max-time 5 http://127.0.0.1:9999/ >/dev/null &&
        curl --fail --silent --max-time 5 \
            -H "Authorization: Bearer $MOUSEHOLE_AUTH_TOKEN" \
            http://127.0.0.1:5010/state |
            jq --exit-status --arg ip "$vpn_ip" --arg since "$started_at" '
                .hasCookie == true and
                .lastMamContact.reached == true and
                .lastMamContact.ip == $ip and
                .lastMamContact.ipUpdate.httpStatus == 200 and
                .lastMamContact.ipUpdate.success == true and
                (.lastMamContact.at[0:19] >= $since)
            ' >/dev/null; then
        break
    fi
    sleep 15
done
echo "MAM confirmed the VPN IP; starting qBittorrent."
unset MOUSEHOLE_AUTH_TOKEN
exec /init
