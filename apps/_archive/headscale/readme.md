### Errors
For an error that looks like:
```
failed to verify id token error="oidc: id token signed with unsupported algorithm, expected [\"RS256\"] got \"HS256\""
```
Go to the `authentik` admin interface, and within System > Certificates, delete the existing keys and auto-generate a new one. Next, edit the OIDC provider to use that specific signing key. Finally, restart the `headscale` service. 