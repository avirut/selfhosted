### Seafile

##### Goals
I've got a couple goals for Seafile:
    1. Generally working base installation w/ website, syncing to clients, etc.
    1. Auth should work against Authentik
    1. OnlyOffice integration built in w/ live collaboration and saving
    1. Mount the actual files to the local filesystem so that code-server can also point to this
    1. Periodic offsite data backups w/ clear recovery plan (e.g., restic-based)

Here are the steps needed to achieve each:

##### 1. Base installation
- Update `.env` and run `docker-compose.yml` with all associated volumes and bind mounts cleared
- Update Seahub settings
    - Enter the container: `docker exec -it seafile /bin/bash`
    - Install a text editor: `apt-get install nano`
    - Update `/opt/seafile/conf/seahub_settings.py`
        - Modify URLs under keys `SERVICE_URL`, `FILE_SERVER_ROOT` to match the reverse proxy if necessary
        - Add trusted origins to pass CSRF - `CSRF_TRUSTED_ORIGINS=["https://subdomain.example.com"]`
- Execute `restart-seafile-and-seahub.sh` - you should now be able to log in

##### 2. Auth with Authentik
- Create an OAuth provider and application in Authentik
- Update Seahub settings, using the keys in `seahub_settings.py.template` as a reference for needed values
- Execute `restart-seafile-and-seahub.sh` - there should now be an SSO option when logging in
- Update admin account
    - Log in once with the SSO account you want to be an admin, then log out
    - Log in with the original admin username and password using non-SSO auth (if this gets messed up somehow, you can always use `/opt/seafile/seafile-server-latest/reset-admin.sh` to make a new admin account inside the Docker container)
    - Go to `System Admin > Users > Admin` and click 'Add Admin' at the top, then add the SSO account as an admin
    - Finally, delete the current, non-SSO admin account entirely - this should log you out
    - When you next log in with the SSO admin account, you should be able to access the admin panel
- Unfortunately, a normal log-in + password field will still show up on the seafile page when logged out, and you'll have to click "Single Sign-On" to log in w/ Authentik - as far as I can tell, the only way to have OAuth only requires [reverse proxy redirection hackiness](https://forum.seafile.com/t/after-enabling-sso-is-it-possible-to-disable-the-password-authentication-and-force-sso/7265/6), so probably not worth it for now

##### 3. OnlyOffice integration
- Instructions on the [Seafile docs](https://manual.seafile.com/deploy/only_office/) more or less hold up, a couple flags:
    - The "Configure Seafile Server" (tagged as 'for OnlyOffice is deployed in a separate machine with a different domain') method is much simpler than running as the same machine, so I went with that and expose OODS on a different subdomain
    - One step involves changing the OODS config to autosave; this does not persist across restarts of the OODS container
        - This is way more brittle than I am normally comfortable with
        - The Seafile docs suggest a bind mount of the OODS config to ensure it persists; I was unable to get this working reliably and therefore would just plan to manually update the OODS config on every restart until I have time to revisit this

##### 4. Mount files to local filesystem
- Original plan here was to use Seafile's built in FUSE extension which enables mounting files to the local filesystem; unfortunately, this is read only, so not viable for my use case of having other apps point to the same directory
- Correspondingly, it seems like the best answer would be to just run a seafile sync client on the same server - this means duplicating data on the same disk, but is unavoidable (unless I want to switch to Nextcloud, which I don't)

##### 5. Recovery & backups
- For now, the hope is that the regular restic backup of `~/selfhosted/data/seafile/store` (which contains underlying blocks), in combination with having the actual files synced to my PC, will be sufficient