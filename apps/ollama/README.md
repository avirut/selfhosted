# Ollama on sophon-gpu

Run this project only in the Linux VM that owns the NVIDIA GPU. Models live on
that guest's SSD under `data/ollama`; persistent ebook services run elsewhere.
Create the data directory before `docker compose up -d`. The pinned official
image was pulled and NVIDIA access checked during provisioning.

The API is bound to guest loopback; private network access is configured
separately. Do not expose the unauthenticated API to the public internet.
One model and one request run at a time initially, with idle models unloaded
after five minutes. Before gaming, use `ollama stop <model>` inside this container
to release that model's GPU allocations. This is not a GPU memory reservation
or a scheduler shared with other workers.

Stop GPU jobs and shut down the guest before handing the entire card to another
VM. The occasional Windows guest and handoff behavior require their own tests.
