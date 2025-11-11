#!/bin/bash

docker exec seafile /opt/seafile/seafile-server-latest/seafile.sh restart
docker exec seafile /opt/seafile/seafile-server-latest/seahub.sh restart