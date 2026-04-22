# DFZ — DevOps From Zero

> Kubernetes & Docker management dashboard. Self-hosted, single-command deploy.

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

Open http://localhost:3080 and sign in with the default credentials below.

### Default credentials

| Field    | Value    |
|----------|----------|
| Username | `admin`  |
| Password | `admin`  |

Change the password immediately from **Settings → Account** after first login.

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
| UI | `ghcr.io/devopsfromzero/dfz-ui` | `${UI_PORT:-3080}` → 3000 |
| Backend | `ghcr.io/devopsfromzero/dfz-backend` | internal 8000 |
| Terminal | `ghcr.io/devopsfromzero/dfz-terminal` | internal 8001 |
| PostgreSQL 16 | `postgres:16-alpine` | internal 5432 |
| Redis 7 | `redis:7-alpine` | internal 6379 |

Only the UI port is exposed to the host. All inter-service traffic stays on the internal `dfz-network` bridge.

## Configuration

All configuration is defined as defaults directly in `docker-compose.yml` — there is no separate `.env` file. To override a default, edit the relevant value in the compose file, then run `docker compose up -d`.

Common overrides (search for the variable name in `docker-compose.yml`):

| Variable | Where it lives | Purpose |
|---|---|---|
| `APP_URL` | `backend.environment` → `CORS_ALLOWED_ORIGINS` | External URL used by the browser (for CORS + cookies) |
| `UI_PORT` | `ui.ports` | Host port mapped to the UI container |
| `SECURE_COOKIES` | `backend` / `terminal` / `ui` environment blocks | Set to `true` when serving behind HTTPS |
| Image `TAG` | Each service's `image:` line | Pin to a specific release (e.g. `:v0.1.0`) |

Rolling back a subsystem (Redis, informers, etc.) or tuning performance knobs? See [`docs/ADVANCED.md`](docs/ADVANCED.md).

## Upgrading

```bash
docker compose pull
docker compose up -d
```

To pin a specific version, replace `:latest` in each `image:` line of `docker-compose.yml` with a versioned tag like `:v0.1.0`, then re-run the pull/up commands. Available tags at [ghcr.io/devopsfromzero](https://github.com/devopsfromzero?tab=packages).

## Troubleshooting

**UI loads but can't log in / CORS error.**
In `docker-compose.yml`, change the default `${APP_URL:-http://localhost:3080}` in the `backend` service's `CORS_ALLOWED_ORIGINS` line to the exact URL you use in the browser (protocol + host + port). Then `docker compose up -d` to apply.

**Cookies not persisting behind a reverse proxy.**
Set `SECURE_COOKIES=true` in the `backend`, `terminal`, and `ui` environment blocks of `docker-compose.yml`. This requires HTTPS end-to-end.

**Backend unhealthy after upgrade.**
Check logs: `docker compose logs backend --tail 100`. If the schema migration failed, restart once more — migrations are idempotent.

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
