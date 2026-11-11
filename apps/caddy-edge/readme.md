### Forward auth

Import the snippet `fa_authentik` into the compose files of other services to enable forward auth.
```yaml
labels:
    caddy.import: fa_authentik "<matcher if needed, otherwise `*`>"
```

In Authentik's admin panel, create a `Proxy Provider`, of type `Forward auth (single application)`. The external host should match the domain of the service, with an `https://` scheme pre-pended. Next, create an application using that provider. Finally, go to the Authentik embedded outpost and add the new application to the selected applications.