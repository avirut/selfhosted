# restic

There's no great Docker-based solution for restic, so these shell scripts are a good option. 

## Setup
### Install restic
```bash
sudo apt-get update
sudo apt-get install restic
restic version
```
Can also just use `install.sh`.

### Make files executable
```bash
chmod +x *.sh
```

## Automating
Install `crontab` to automate the running of `backup.sh` and `remove-old.sh`.
```
sudo apt-get update
sudo apt-get install cron
```
    
Then, edit the `sudo` crontab file:
```
sudo crontab -e
```

Use [crontab.guru](https://crontab.guru/) to generate the cron schedule. For example, to run the backup at 4:45 AM every day, use:
```
45 4 * * * cd /home/avirut/selfhosted/apps/restic && ./backup.sh > /home/avirut/selfhosted/data/restic/backup.log 2>&1
```

On a single host only (likely the VPS), run the `remove-old.sh` script at a time when no other backups are running. For example, to run the script at 5:00 PM every day, use:
```bash
0 17 * * * cd /home/avirut/selfhosted/apps/restic && ./remove-old.sh > /home/avirut/selfhosted/data/restic/remove-old.log 2>&1
```

In order to get logs, make a restic folder in the datadir:
```bash
sudo mkdir -p ~/selfhosted/data/restic
```

## Shell scripts
### install.sh
Simply installs restic to /usr/local/bin/restic.

### create-repo.sh
Creates a restic repository to backblaze based on the values in `.env`.

### backup.sh
Backs up the specified directory from `.env` to the restic repository.

### remove-old.sh
Removes old backups from the restic repository. This should only be run on one host, and at a time when no other backups are running. E.g. for backups in the early AM, this can be run in the afternoon.

### recover.sh
No good shell script here - just refer to the documentation to do what's needed.