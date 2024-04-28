import sys, os
import json

# get directory of this file
dir_path = os.path.dirname(os.path.realpath(__file__))

# create a path string to a .env file in the same directory as this file
env_path = os.path.join(dir_path, ".env")
hm_path = os.path.join(dir_path, "hostmap.json")

# read in .env and create a dictionary
env = {}
with open(env_path) as f:
    for line in f:
        (key, val) = line.split("=")
        env[key] = val.strip()

# read in the hostmap file and create a dictionary
hostmap = {}
with open(hm_path) as f:
    hostmap = json.load(f)

routes = []
for host, subdomains in hostmap.items():
    # replace all environment variable interpolations in subdomains with their values from env
    # keeping in mind that interpolations will follow the ${} format
    for i, subdomain in enumerate(subdomains):
        for key, val in env.items():
            subdomains[i] = subdomains[i].replace("${" + key + "}", val)

    # create a caddy route for each host
    routes.append({
        "match": [
            {
                "tls": {
                    "sni": subdomains
                }
            },
            {
                "http": [
                    {
                        "host": subdomains
                    }
                ]
            }
        ],
        "handle": [
            {
                "handler": "proxy",
                "upstreams": [
                    {
                        "dial": [host]
                    }
                ]
            }
        ]
    })

caddy = {
    "apps": {
        "layer4": {
            "servers": {
                "ingress_rp": {
                    "listen": [
                        ":443"
                    ],
                    "routes": routes
                }
            }
        }
    }
}

print(json.dumps(caddy))avirut@janus:~/selfhosted/apps/caddy-ingress$ cat convert_hostmap_to_caddy.py
import sys, os
import json

# get directory of this file
dir_path = os.path.dirname(os.path.realpath(__file__))

# create a path string to a .env file in the same directory as this file
env_path = os.path.join(dir_path, ".env")
hm_path = os.path.join(dir_path, "hostmap.json")

# read in .env and create a dictionary
env = {}
with open(env_path) as f:
    for line in f:
        (key, val) = line.split("=")
        env[key] = val.strip()

# read in the hostmap file and create a dictionary
hostmap = {}
with open(hm_path) as f:
    hostmap = json.load(f)

routes = []
for host, subdomains in hostmap.items():
    # replace all environment variable interpolations in subdomains with their values from env
    # keeping in mind that interpolations will follow the ${} format
    for i, subdomain in enumerate(subdomains):
        for key, val in env.items():
            subdomains[i] = subdomains[i].replace("${" + key + "}", val)

    # create a caddy route for each host
    routes.append({
        "match": [
            {
                "tls": {
                    "sni": subdomains
                }
            },
            {
                "http": [
                    {
                        "host": subdomains
                    }
                ]
            }
        ],
        "handle": [
            {
                "handler": "proxy",
                "upstreams": [
                    {
                        "dial": [host]
                    }
                ]
            }
        ]
    })

caddy = {
    "apps": {
        "layer4": {
            "servers": {
                "ingress_rp": {
                    "listen": [
                        ":443"
                    ],
                    "routes": routes
                }
            }
        }
    }
}

print(json.dumps(caddy))