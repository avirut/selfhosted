# Hosts
### Auth + VPN + Reverse proxy
The first host, which must have a static IP, runs authentication and a VPN behind a reverse proxy, along with routing traffic to other notes. Currently, Authentik is used for authentication, Headscale is used for the VPN, and Caddy is used to reverse proxy. To set up this host, follow the steps below.
1. Initial setup
1. Restic setup (w/ cronjobs for `backup.sh` and `remove-old.sh`)
1. Run containers (Caddy and Authentik must be the first and second, respectively)
    1. Caddy-ingress
        1. Edit `hostmap.json` to include the domain name and any subdomains that will be used
        1. Generate a `caddy-ingress.json` file using `reload-caddy-json.sh`
        1. Bring up the ingress container
    1. Caddy-docker-proxy
        - run `docker network create cdp` before bringing the container up
    1. Authentik
        - after bringing up authentik, create a user for yourself and another for `servers`
        - create a `headscalars` group and add any users that should be able to access the `headscale` server
        - create an OIDC provider, then create an application for `headscale` using that provider
    1. Headscale
        - update the `.env` file with the OIDC provider and application details, as well as the domain name and other details
    1. Static-file-server
    1. Uptime Kuma
1. Tailscale setup

### Worker nodes
Subsequently, as many nodes as desired can be added, with or without static IPs. To set up a worker node, follow the steps below.
1. Initial setup
1. Restic setup (w/ cronjobs for `backup.sh` *only*)
1. Tailscale setup + join the network
1. Run containers
    1. Caddy (use caddy-docker-proxy here)
        - run `docker network create cdp` before bringing the container up
    1. Any subdomains that will be used must be added to the `hostmap.json` file on the auth host, and the `caddy-ingress.json` file must be regenerated and loaded using `reload-caddy-json.sh`

# Steps
### Initial setup
If on a VPS with an automatically created user, you can optionally pick a new username as desired:
```bash
export NAME=avirut
```

Next, create a new user with the same username as the automatically created user, add it to the `sudo` group, and copy over the SSH keys from the automatically created user:
```bash
sudo adduser $NAME
sudo usermod -aG sudo $NAME
sudo mkdir /home/$NAME/.ssh
sudo chmod 700 /home/$NAME/.ssh
sudo cp ~/.ssh/authorized_keys /home/$NAME/.ssh/authorized_keys
sudo chown -R $NAME:$NAME /home/$NAME/.ssh
sudo chmod 600 /home/$NAME/.ssh/authorized_keys
```

Finally, SSH in with the new username and delete the automatically created user:
```bash
sudo deluser --remove-home <automatically created user>
```

Set the timezone as appropriate:
```bash
sudo timedatectl set-timezone America/Chicago
timedatectl
```

Next, install Docker by following the [official instructions](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository).

Complete the suggested post-installation steps:
```bash
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
```

Test docker by running the hello-world container:
```bash
docker run hello-world
```
### Tailscale setup
Download and install Tailscale from the [official website](https://tailscale.com/download).
Login with:
```bash
sudo tailscale up --login-server https://hs.${DOMAIN}
```
Complete the printed steps to authorize the device.

### Swarm setup
For Docker swarm to work, certain ports must be open on all hosts. First, ensure that any swarm hosts with managed network ingress rules (e.g., on Oracle Cloud) have the appropriate ports open through the web GUI. These ports are:
- 2377/tcp
- 7946/tcp
- 7946/udp
- 4789/udp
- 2376/tcp

Both above and below, we can open hosts only to the tailnet IP range, i.e., `100.64.0.0/10`.  

Then, on all swarm hosts, use `firewalld` to edit `iptables`:
```bash
sudo apt install firewalld
sudo systemctl enable firewalld

sudo firewall-cmd --permanent --zone=public --add-port=2377/tcp
sudo firewall-cmd --permanent --zone=public --add-port=7946/tcp
sudo firewall-cmd --permanent --zone=public --add-port=7946/udp
sudo firewall-cmd --permanent --zone=public --add-port=4789/udp
sudo firewall-cmd --permanent --zone=public --add-port=2376/udp
sudo firewall-cmd --reload
```

Next, initialize the swarm:
```bash
docker swarm init --advertise-addr <tailnet IP>
```

Finally, add the other hosts to the swarm:
```bash
docker swarm join-token worker # get the token from the swarm manager
```
Run the command printed above on other hosts, adding in `--advertise-addr <tailnet IP>`.

Create a Docker overlay network for the swarm:
```bash
docker network create --driver overlay --attachable --subnet
```

# Debugging
### Docker swarm networking
If you see an error that looks like:
```
docker: Error response from daemon: error creating external connectivity network: Failed to Setup IP tables: Unable to enable SKIP DNAT rule:  (iptables failed: iptables --wait -t nat -I DOCKER -i docker_gwbridge -j RETURN: iptables: No chain/target/match by that name.
```
Then, try restarting Docker:
```bash
sudo systemctl restart docker
```
