# uptime-kuma

### Usage
- add in Docker sockets - volume is mapped, so simply go to `Settings > Docker Hosts` and add `/var/run/docker.sock` there. Afterwards you can use the `Docker Container` monitor type to monitor uptime by container name. 
- cron jobs (e.g. for restic) can be monitored with monitor type `Push`