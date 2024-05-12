set -o allexport
source .env
set +o allexport

docker exec -t rclone rclone sync /data DEFAULT:${BUCKET_NAME} --progress --fast-list --rc-addr /tmp/rclone-backup-running