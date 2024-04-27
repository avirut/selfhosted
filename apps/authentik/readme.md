### Authentik setup
1. Fill out missing values in `.env` - use `pwgen` with `sudo apt install pwgen` to simplify creating `PG_PASS` and `AUTHENTIK_SECRET_KEY`.
1. Bring up the container with `docker-compose up -d` and wait 2-5 mins for everything to start. Verify that Authentik is running with `docker logs authentik`.
1. Navigate to `https://auth.${DOMAIN}/if/flow/initial-setup` to create the admin account.

### Using Authentik
- Go to `Directory/Users` in the Authentik sidebar to create users.
- Create a provider to integrate with other services. All information you need to integrate should be located within the provider itself; the application is only secondary.

### Custom logo and favicon
- Make sure that the assets in `./assets` match the assets you want.
- In the admin interface, look under `System`/`Tenants` and edit the default tenant. Under `Branding settings`, you can set a title, logo, and favicon. The logo path will be `/media/custom/logo.svg` and the favicon will be `/media/custom/favicon.ico`. 
- Under `Flows & Stages` > `Flows`, edit the `default-authentication-flow`. Change the name, title, and set the background image as desired.