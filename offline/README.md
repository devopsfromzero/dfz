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

Download the next bundle and extract it **over this directory** — the archive
carries only the bundle's own files, so your `config.env`, `.env`, `backups/`
and the rollback record stay exactly where they are. Then:

```bash
cd ..                                # the directory ABOVE this one
tar xzf dfz-offline-amd64.tar.gz     # replaces ./dfz-offline-amd64 in place
cd dfz-offline-amd64
./install.sh --status     # what is installed, what this bundle would change
./install.sh              # upgrade
```

The directory name is deliberately stable: with a dated one, `cd
dfz-offline-*-amd64` stops being unambiguous the moment a second bundle is on
the host, and running the older bundle's installer by accident is a mistake with
no signal. Which bundle you have is in `VERSION`, and `install.sh` prints it on
its first line.

The upgrade, in order: it finds your existing stack, prints the plan
(component by component, installed → bundle), **dumps the database** to
`backups/`, records the current versions for `--rollback`, starts the new
containers, and then **verifies** that what is running really is the image this
bundle carries — comparing image IDs, not tags. If it is not, it says so and
exits non-zero instead of reporting success.

Your data lives in Docker volumes and stays where it is.

```bash
./install.sh --rollback   # back to the previous set (its images are still here)
./install.sh --no-backup  # skip the dump — not recommended
```

**If you installed before 2026-07-29**, your stack runs under a compose project
named after the directory you extracted that bundle into (for example
`dfz-offline-20260728-amd64`), because the project name was not pinned yet.
The installer detects that and keeps using it, so nothing moves. Two things
follow from it:

- If you upgrade WITHOUT `install.sh`, pass the project explicitly, or Compose
  will start a second, empty stack beside your data:

  ```bash
  docker inspect dfz-backend \
    --format '{{index .Config.Labels "com.docker.compose.project"}}'
  ./install.sh --load-only                                            # load the images
  docker compose -p <that-project> up -d                              # upgrade in place
  ```

- Every plain `docker compose` command you run for that stack needs the same
  `-p <project>`. New installs do not: they use the pinned name `dfz`.

## Uninstall

```bash
docker compose down          # stop the stack; your data stays in its volumes
```

To delete the data as well — the database, the stored credentials and the key
that decrypts them — you must name the volumes yourself:

```bash
docker compose down
docker volume ls | grep -E 'postgres-data|backend-secrets'   # look first
docker volume rm <project>_postgres-data <project>_backend-secrets
```

`docker compose down -v` does the same thing in one keystroke and is not
written out here on purpose: it is one character away from the safe command,
and there is no undo.

## If something goes wrong

**`docker login` fails on TLS.** A registry served over plain HTTP, or with a
self-signed certificate, has to be named in the Docker daemon's config:
`insecure-registries` in `/etc/docker/daemon.json`, then restart docker. Confirm
it took with `docker info` — the host should be listed under "Insecure
Registries". Plain-HTTP registries are fully supported; the installer detects
this setting and checks the address over HTTP accordingly.

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
