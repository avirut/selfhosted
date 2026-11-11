### Steps to set up RClone in Docker

1. Make .htpasswd file and place it in ./config
2. Add rclone.conf file to ./config
    - If you don't already have one, run the container without it, and then enter the container (`docker exec -it rclone /bin/sh`) and use the rclone command to generate a config
3. Add htpasswd file to ./config
    - `touch .htpasswd`
    - `htpasswd -B .htpasswd <USER>`
4. Add `sync.sh` to crontab on user system - this doesn't seem to work within the docker container, although that would be ideal
    - `sudo crontab -e` to add to superuser crontab
    - add line `*/15 * * * * cd ~/selfhosted/apps/rclone && ./sync.sh` to sync every 15 minutes