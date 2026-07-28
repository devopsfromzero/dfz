# DFZ — offline install

Everything this stack needs is in this directory. Nothing is downloaded during
the install: the container images travel with it, and so do the compose file and
the edge config.

## What you have

```
install.sh              the installer
config.env.example      settings to copy and fill in
docker-compose.yml      the stack — the same file the online install uses
Caddyfile               edge config
VERSION                 which component versions are inside
images/images.tar       every container image
images/manifest.txt     what is in that tar
```

## Requirements

Docker Engine 24.0+ and Compose v2.20+, 4 GB RAM, and roughly 10 GB of free
disk on the machine you extract this on — the images are loaded out of the tar
before the tar itself can be deleted.

## Two ways to install

### Mirror into your registry (recommended)

Use this if you will connect Kubernetes clusters. Each cluster pulls the agent
image itself, so the image has to live somewhere the cluster can reach.

```bash
cp config.env.example config.env
$EDITOR config.env          # REGISTRY, credentials, APP_URL
./install.sh
```

The installer loads the images, logs in, tags and pushes all of them to your
registry, writes a `.env` that points the compose file at it, and starts the
stack. The password is fed to `docker login` on stdin — never as a command-line
argument, where every user on the host could read it out of `ps`.

Two things to get right in `config.env`:

- **The address.** Use exactly what your registry tells you to use for
  `docker login` — some registries serve their Docker API on a port of their
  own rather than on 443, and that port belongs in `REGISTRY`. Everything after
  the host is the namespace your images land in, not part of the address.
  `install.sh` checks this before it loads anything, so a wrong address costs
  seconds rather than minutes.
- **The namespace.** Many registries reject a push into a namespace they were
  not told to create. Create it in the registry's UI first, and make sure the
  account can write to it.

### Run straight from the local images

```bash
./install.sh --no-registry
```

No registry, no credentials. The dashboard, Docker hosts, and any cluster this
host can reach with a kubeconfig all work.

In-cluster Kubernetes agents do **not** — a cluster cannot pull from this host's
Docker daemon. To add them later, push the agent image somewhere your clusters
can reach and set that registry in **Settings → Security → Container registry**.
The installer prints the exact two commands when it finishes in this mode.

### Other options

| Flag | Effect |
|---|---|
| `--load-only` | Load the images and stop. Nothing pushed, nothing started. |
| `--config FILE` | Read settings from somewhere other than `./config.env`. |
| `--dry-run` | Print every step without changing anything. |

Any setting in `config.env` can be passed as an environment variable instead,
which takes precedence — useful when a credential should not be written to disk.

## After the install

Open the URL the installer prints. You will be asked to create the admin
account on first open; there is no default password.

Then, in the UI:

- **Settings → Security → Server URL** — the address agents dial back to. It has
  to be reachable *from your clusters*, not just from your browser.
- **Settings → Security → Container registry** — the registry the add-cluster
  wizard offers by default. `install.sh` pushed the agent image to your
  registry; setting it here means nobody has to type it again for each cluster.
  The add-cluster wizard can still override it per cluster.

If your registry needs credentials to pull, create the pull secret in each
cluster and name it in the same settings page (or per cluster in the wizard).
DFZ only ever references that secret by name — it never sees the credentials.

## Upgrading

Download the next bundle, extract it beside this one, and run its `install.sh`
with the same `config.env`. It pushes the new image versions and restarts the
stack; your data lives in Docker volumes and is untouched.

## Uninstall

```bash
docker compose down          # stop, keep data
docker compose down -v       # also delete the volumes — this deletes your data
```

## If something goes wrong

**`docker login` fails.** Usually TLS: the host has to trust the registry's
certificate. Check `docker info` for the registry under "Insecure Registries" if
you use a self-signed one.

**A push is rejected.** The namespace has to exist and the account needs write
access to it. The installer prints what the registry said, so read that line
first — "not found" points at the address or the namespace, "unauthorized" at
the account's permissions on it.

**"serves no Docker registry API at /v2/".** The address in `REGISTRY` is not
the one the registry expects for `docker login` — most often a missing port.
Check the registry's UI for the address it publishes.

**`image not found locally`.** The stack is set to `PULL_POLICY=never`, which is
deliberate — it fails fast instead of hanging on a registry it cannot reach.
Re-run `./install.sh --load-only` to reload the images.

**Backend unhealthy for a few minutes on first boot.** It is running schema
migrations. `docker compose logs backend --tail 100` shows where it is.
