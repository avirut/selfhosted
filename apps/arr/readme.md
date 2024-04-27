### Notes
- Mount external hard disk to /mnt/data with the following structure:
    - /mnt/data (external hard disk)
        - media
            - movies
            - tv
        - torrents
            - movies
            - tv

- Bring up the docker containers - config should be restored from backups, ideally. If config is lost, restart with the TRaSH and arr-wiki guides.
    - key differences for me in Sonarr/Radarr configs
        - do use the profiles and custom formats (in general), but do not adjust the quality min/preferred/max settings - the recommended values in TRaSH guides lead to selecting files that are way larger than they need to be
        - allow h265 within custom formats, no need to give it an extremely negative score - h265 is preferable as transcoding won't be required, but our server should have hardware acceleration for transcoding

- How do things work?
    - Doplarr sends requests to Sonarr/Radarr (and correspondingly requires API keys for both)
    - Sonar and Radarr use their indexers, which are synced and maintained in working order by Prowlarr, to search for the requested content
    - Sonarr/Radarr select the best torrent and subsequently pass it to rdtclient to interface with Real-Debrid
    - Rdtclient uses Real-Debrid credentials to get the torrent from Real-Debrid and generate download links, which are then passed to aria2c to download the content
    - When the aria2c download is complete, Rdtclient will let Sonarr/Radarr know, and they will import the content into the appropriate folder

- Setting stuff up
    - Doplarr: setup using their [documentation](https://kiranshila.github.io/Doplarr/#/) to get a Discord bot up and running
    - Sonarr/Radarr: setup using the [TRaSH guides](https://trash-guides.info/guides/sonarr/) and [arr-wiki](https://wiki.servarr.com/) to get the basics up and running, with adjustments as suggested above
    - Prowlarr: setup using the [arr-wiki](https://wiki.servarr.com/prowlarr) to get the basics up and running - good indexers are KAT, 1337x, YTS, and LimeTorrents (in roughly that order)
    - ariang: refer to [documentation](https://hub.docker.com/r/hurlenko/aria2-ariang) - ariang, which will be present at the domain specified, is a web interface for aria2c
        - ariang keeps credentials in cookies local to the browser, so authentication is not necessary (but might as well?)
        - ariang is not necessary, only the actual aria2c instance, but it's a nice way to monitor downloads
        - aria2c instance will be accessible at the domain specified with port from docker-compose file
    - Rdtclient: refer to [documentation](https://github.com/rogerfar/rdt-client)
        - categories should be 'movies' and 'tv', coming from Radarr and Sonarr respectively
        - set download client to Aria2c, download path and mapped path to `/mnt/data/torrents`, and add in aria2c url in form `https://${ARIA_DOMAIN}:${ARIA_PORT}/jsonrpc`; add in the Aria2c secret specified in .env as well and test the connection