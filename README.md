# DFZ — DevOps From Zero

> Kubernetes & Docker management dashboard. Self-hosted, single-command deploy.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Images](https://img.shields.io/badge/images-ghcr.io-blue)](https://github.com/devopsfromzero?tab=packages)

DFZ gives you a single UI to manage Kubernetes clusters, Docker hosts, terminals, and deployment workflows — all running from your own infrastructure.

## Quick start

```bash
git clone https://github.com/devopsfromzero/dfz-deploy.git
cd dfz-deploy
cp .env.example .env      # edit APP_URL / UI_PORT if needed
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

Everything is configured via environment variables in `.env`. See [`.env.example`](.env.example) for the full list.

Most common overrides:

```env
APP_URL=https://dashboard.example.com   # must match your access URL for CORS
UI_PORT=8080                             # change if 3080 is taken
SECURE_COOKIES=true                      # enable when behind HTTPS
TAG=v0.1.0                               # pin to a specific release
```

## Upgrading

```bash
docker compose pull
docker compose up -d
```

To pin a version, set `TAG` in `.env` and repeat. Available tags at [ghcr.io/devopsfromzero](https://github.com/devopsfromzero?tab=packages).

## Troubleshooting

**UI loads but can't log in / CORS error.**
Set `APP_URL` in `.env` to the exact URL you use in the browser (protocol + host + port), then `docker compose up -d` to apply.

**Cookies not persisting behind a reverse proxy.**
Set `SECURE_COOKIES=true` in `.env`. This requires HTTPS end-to-end.

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

Found a bug or have a feature request? [Open an issue](https://github.com/devopsfromzero/dfz-deploy/issues).

## License

MIT — see [LICENSE](LICENSE).
