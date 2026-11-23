#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
server=${1:-/var/lib/pelican/volumes/6c61b5af-b241-433c-bfc8-19e546e17b75}
image=ghcr.io/pelican-eggs/yolks:java_25
out=$here/build
owner=$(stat -c %u:%g "$here")

rm -rf "$out"
mkdir -p "$out/classes"
python3 "$here/icons.py" "$out"
mv "$out/icons.txt" "$out/classes/icons.txt"
cp "$here/plugin.yml" "$here/config.yml" "$out/classes/"

docker run --rm --network none --user 0:0 \
    -v "$here:/src:ro" -v "$out:/out" \
    -v "$server/versions:/server/versions:ro" -v "$server/libraries:/server/libraries:ro" \
    --entrypoint sh "$image" -c '
        set -e
        cp=$(find /server/versions /server/libraries -name "*.jar" | sort | tr "\n" ":")
        javac --release 25 -Xlint:-options -d /out/classes -cp "$cp" $(find /src/src -name "*.java")
        jar --create --file /out/waymarks.jar --date 1980-01-02T00:00:00Z -C /out/classes .
    '
chown -R "$owner" "$out"
sha1sum "$out/waymarks-pack.zip" | cut -d" " -f1 > "$out/waymarks-pack.sha1"
ls -l "$out/waymarks.jar" "$out/waymarks-pack.zip"
cat "$out/waymarks-pack.sha1"
