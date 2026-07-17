# DFZ — DevOps From Zero

> Kubernetes & Docker management dashboard. Self-hosted, single-command deploy.

[![Website](https://img.shields.io/badge/website-devopsfromzero.com-7dd3fc)](https://www.devopsfromzero.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Images](https://img.shields.io/badge/images-ghcr.io-blue)](https://github.com/devopsfromzero?tab=packages)

DFZ gives you a single UI to manage Kubernetes clusters, Docker hosts, terminals, and deployment workflows — all running from your own infrastructure.

## Quick start

```bash
git clone https://github.com/devopsfromzero/dfz.git
cd dfz
docker compose pull
docker compose up -d
```

Open http://localhost:3080. On first launch you'll be prompted to create the admin account (username and password) — there is no default password to fall back on.

## Requirements

| Requirement | Minimum | Recommended |
|---|---|---|
| Docker Engine | 24.0+ | 27.0+ |
| Docker Compose | v2.20+ | v2.30+ |
| RAM | 4 GB | 8 GB |
| CPU | 2 cores | 4 cores |
| Disk | 5 GB | 20 GB (+ volumes) |

No external database or Redis needed — both ship in the compose file.

## Services

| Service | Image | Port |
|---|---|---|
| Caddy edge | `caddy:2-alpine` | `${UI_PORT:-3080}` → 3080 (the ONLY published port) |
| UI | `ghcr.io/devopsfromzero/dfz-ui` | internal 3000 |
| Backend (API) | `ghcr.io/devopsfromzero/dfz-backend` | internal 8000 |
| Worker (background jobs) | `ghcr.io/devopsfromzero/dfz-backend` | internal 8000 |
| Terminal | `ghcr.io/devopsfromzero/dfz-terminal` | internal 8001 |
| Gateway (agent tunnels) | `ghcr.io/devopsfromzero/dfz-gateway` | internal 3091/3092 |
| PostgreSQL 16 | `postgres:16-alpine` | internal 5432 |
| Redis 7 | `redis:7-alpine` | internal 6379 |

Only the Caddy edge port is exposed to the host; it serves the app and the `/agent-tunnel` websocket on the same port. All inter-service traffic stays on the internal `dfz-network` bridge.

**Connecting clusters:** each Kubernetes cluster is managed by a small agent (`ghcr.io/devopsfromzero/dfz-agent`) running *inside* that cluster. The add-cluster wizard in the UI generates its manifest; the agent dials out to this stack over the `/agent-tunnel` websocket — no inbound access to your clusters is required.

## Configuration

All configuration is defined as defaults directly in `docker-compose.yml` — there is no separate `.env` file. To override a default, edit the relevant value in the compose file, then run `docker compose up -d`.

Common overrides (search for the variable name in `docker-compose.yml`):

| Variable | Where it lives | Purpose |
|---|---|---|
| `APP_URL` | `x-app-env` → `CORS_ALLOWED_ORIGINS` / `DFZ_AGENT_SERVER_URL` | External URL used by the browser and dialed by cluster agents |
| `UI_PORT` | `caddy.ports` | Host port of the Caddy edge |
| `SECURE_COOKIES` | `x-app-env` + `terminal` / `ui` environment blocks | Set to `true` when serving behind HTTPS |
| `BACKEND_TAG` / `UI_TAG` / `TERMINAL_TAG` / `AGENT_TAG` / `GATEWAY_TAG` | Each service's `image:` line | Override a service's version (components version independently; each falls back to `TAG`, then to the tested default this commit pins) |

Rolling back a subsystem (Redis, informers, etc.) or tuning performance knobs? See [`docs/ADVANCED.md`](docs/ADVANCED.md).

## Upgrading

```bash
git pull
docker compose pull
docker compose up -d
```

Each service's `image:` line in `docker-compose.yml` pins the version this commit was tested with, so any clone of a given commit runs exactly the same stack. `git pull` moves you to the next released set — the compose file, the edge config and the pins travel together. To see what you're currently pinned to:

```bash
docker compose config | grep image:
```

Want the bleeding edge instead of the tested set? `TAG=latest docker compose up -d`. Need a single component on a different version? Use its override (`BACKEND_TAG`, `UI_TAG`, `TERMINAL_TAG`, `AGENT_TAG`, `GATEWAY_TAG`) — each falls back to `TAG`, then to the pinned default.

Available tags at [ghcr.io/devopsfromzero](https://github.com/devopsfromzero?tab=packages).

## Troubleshooting

**UI loads but can't log in / CORS error.**
In `docker-compose.yml`, change the default `${APP_URL:-http://localhost:3080}` in the shared `x-app-env` block (`CORS_ALLOWED_ORIGINS`) to the exact URL you use in the browser (protocol + host + port). Then `docker compose up -d` to apply.

**Cookies not persisting behind a reverse proxy.**
Set `SECURE_COOKIES=true` in the `backend`, `terminal`, and `ui` environment blocks of `docker-compose.yml`. This requires HTTPS end-to-end.

**Backend unhealthy after upgrade.**
Check logs: `docker compose logs backend --tail 100`. If the schema migration failed, restart once more — migrations are idempotent.

**Cluster shows Disconnected / agent can't connect.**
The agent dials `APP_URL` + `/agent-tunnel` from *inside* the cluster, so that URL must be reachable from the cluster's nodes (not just your browser) — `localhost` won't work for a remote cluster. Check `docker compose logs caddy gateway --tail 50` for the incoming tunnel, and the agent pod's logs in the cluster for dial errors. Behind HTTPS the agent uses `wss://<host>/agent-tunnel` automatically.

**Data lives in which volumes?**
- `postgres-data` — all application state (users, cluster configs, settings)
- `backend-secrets` — encryption key (⚠️ never delete; losing it makes stored kubeconfigs unrecoverable)
- `redis-data` — cache only, safe to delete

Back up `postgres-data` and `backend-secrets` together.

## Uninstall

```bash
docker compose down          # stop and remove containers (keeps data)
docker compose down -v       # also delete volumes (⚠️ deletes your data)
```

## Support

Found a bug or have a feature request? [Open an issue](https://github.com/devopsfromzero/dfz/issues).

## License

MIT — see [LICENSE](LICENSE).
