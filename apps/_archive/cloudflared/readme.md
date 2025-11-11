Primarily sourced from [this](https://archive.ph/UPzQW) tutorial!

Authorize cloudflared:
```bash
docker run -v ${PWD}/config:/root/.cloudflared msnelling/cloudflared cloudflared tunnel login
```
Create a cloudflared tunnel:
```bash
TNAME=$(hostname)
docker run -v ${PWD}/config:/etc/cloudflared msnelling/cloudflared cloudflared tunnel create $TNAME
```
Add the new tunnel's UUID to `config/config.yml`, as well as appropriate domains to the ingress rules.