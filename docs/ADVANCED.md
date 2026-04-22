# Advanced Configuration

Every knob exposed as a default in [`docker-compose.yml`](../docker-compose.yml) is the short list operators actually need. This file covers the long tail — internal feature flags, performance tuning beyond the defaults, and rollback paths.

Everything listed here is **optional**. The defaults ship in the container image; you don't need to set any of these for a working install. They exist so you can disable a misbehaving subsystem without rebuilding an image.

## How overrides work

All flags are read from environment variables at backend startup. To override one, edit the `docker-compose.yml` file directly: add the flag to the `environment:` block of the service that reads it (usually `backend`), then apply:

```bash
docker compose up -d
```

Example — adding two overrides to the `backend` service's `environment:` block in `docker-compose.yml`:

```yaml
    environment:
      # ... existing entries ...
      - USE_REDIS_CACHE=false
      - INFORMER_PODS_ENABLED=false
```

Boolean flags accept: `true`, `1`, `yes`, `on` (case-insensitive). Anything else is treated as false.

## Feature flags — what each one does

All flags default to **ON**. Set to `false` only to diagnose or roll back a specific feature.

### Faz 1 — Performance primitives

| Flag | Default | What it does | When to disable |
|------|---------|--------------|-----------------|
| `SINGLEFLIGHT_ENABLED` | `true` | Coalesces concurrent identical requests into one upstream call (thundering-herd guard) | Debugging why a single request path fans out unexpectedly |
| `SWR_CACHE_ENABLED` | `true` | Stale-while-revalidate caching on hot read paths | You see stale values and want to force fresh reads every time |
| `DASHBOARD_SNAPSHOT_JOB_ENABLED` | `true` | Background job that pre-builds dashboard overview data | Background job misbehaves and you want to fall back to on-demand compute |
| `RBAC_CACHE_ENABLED` | `true` | 60 s cache of profile ownership checks | RBAC changes must propagate instantly (rare; wait 60 s or restart) |

### Faz 2 — Redis + async K8s client

| Flag | Default | What it does |
|------|---------|--------------|
| `USE_REDIS_CACHE` | `true` | Route cache through Redis instead of per-worker memory. Falls back to in-memory automatically if Redis is unhealthy. |
| `USE_DISTRIBUTED_SINGLEFLIGHT` | `true` | Coalesces identical requests *across* worker processes via a Redis lock. No-op if `USE_REDIS_CACHE=false`. |
| `USE_BACKEND_PAGINATION` | `true` | Uses the Kubernetes `continue` token to page through large resource lists server-side. |

Per-resource async K8s flags — each controls whether that resource type uses the native `kubernetes_asyncio` path:

```
USE_ASYNC_K8S_DEPLOYMENTS
USE_ASYNC_K8S_STATEFULSETS
USE_ASYNC_K8S_DAEMONSETS
USE_ASYNC_K8S_SERVICES
USE_ASYNC_K8S_NAMESPACES
USE_ASYNC_K8S_CONFIGMAPS
USE_ASYNC_K8S_SECRETS
USE_ASYNC_K8S_NODES
USE_ASYNC_K8S_REPLICASETS
USE_ASYNC_K8S_JOBS
USE_ASYNC_K8S_CRONJOBS
```

All default to `true`. Disabling one forces that resource type through the legacy synchronous path.

> **Retired flags.** `USE_ASYNC_K8S_PODS` and `USE_ASYNC_K8S_METRICS` are no longer read — pods and metrics are async-only now. Setting them has no effect.

### Faz 3 — Informer cache + SSE push

| Flag | Default | What it does |
|------|---------|--------------|
| `USE_INFORMER_CACHE` | `true` | Master switch — reads go through the in-process informer cache first, falling back to direct K8s calls on miss. |
| `USE_SSE_PUSH` | `true` | Pushes resource updates to the UI over Server-Sent Events instead of forcing it to poll. |
| `INFORMER_TIERED_STRATEGY` | `true` | HOT/WARM/COLD cluster tier management — idle clusters get evicted to free memory. |

Per-resource informer toggles — each decides whether an informer is *started* for that resource type:

```
INFORMER_PODS_ENABLED
INFORMER_DEPLOYMENTS_ENABLED
INFORMER_SERVICES_ENABLED
INFORMER_STATEFULSETS_ENABLED
INFORMER_DAEMONSETS_ENABLED
INFORMER_NAMESPACES_ENABLED
INFORMER_NODES_ENABLED
INFORMER_CONFIGMAPS_ENABLED
INFORMER_SECRETS_ENABLED
INFORMER_REPLICASETS_ENABLED
INFORMER_JOBS_ENABLED
INFORMER_CRONJOBS_ENABLED
INFORMER_ENDPOINTS_ENABLED
INFORMER_INGRESS_ENABLED
INFORMER_PERSISTENTVOLUMES_ENABLED
INFORMER_PERSISTENTVOLUMECLAIMS_ENABLED
```

All default to `true`. Disabling one stops the informer for that type; reads still work but pay a full K8s round-trip every time.

## Performance tuning

These are already exposed as defaults in [`docker-compose.yml`](../docker-compose.yml) on the `backend` service under *Resource tuning* — documented here for completeness.

| Variable | Default | Notes |
|----------|---------|-------|
| `THREAD_POOL_MAX_WORKERS` | `64` | asyncio default executor size. Bumping this past `PG_POOL_MAX_SIZE × 3` can cause Postgres pool starvation. |
| `PG_POOL_MIN_SIZE` | `2` | Minimum live asyncpg connections per backend worker. |
| `PG_POOL_MAX_SIZE` | `20` | Cap per backend worker. Multiply by uvicorn `--workers` to size Postgres. |
| `REDIS_MAX_CONNECTIONS` | `50` | Per-worker redis-py pool. |
| `INFORMER_PROCESS_SOFT_LIMIT_MB` | `1500` | Soft cap for the informer manager process. |
| `INFORMER_PROCESS_HARD_LIMIT_MB` | `2000` | Hard cap — informer manager restarts if it goes above. |

### Informer tier sizing

If you manage many clusters, tune the tier thresholds so idle clusters evict cleanly:

| Variable | Default | Notes |
|----------|---------|-------|
| `INFORMER_MAX_CLUSTERS` | `30` | Absolute cap — oldest clusters beyond this are stopped. |
| `INFORMER_HOT_LIMIT` | `10` | Clusters kept fully live (all informer types running). |
| `INFORMER_WARM_LIMIT` | `20` | Clusters kept with a minimal informer set. |
| `INFORMER_HOT_THRESHOLD` | `300` (s) | Activity window to stay HOT. |
| `INFORMER_WARM_THRESHOLD` | `1800` (s) | Activity window to stay WARM before going COLD. |
| `INFORMER_RECONCILE_INTERVAL` | `60` (s) | How often the manager re-ranks tiers. |

### Distributed singleflight tunables

Only relevant when `USE_DISTRIBUTED_SINGLEFLIGHT=true` (the default). Most installs never touch these.

| Variable | Default | Notes |
|----------|---------|-------|
| `DIST_SF_LOCK_TTL` | `30` (s) | Max time a leader holds the lock before Redis auto-expires it. |
| `DIST_SF_RESULT_TTL` | `30` (s) | How long the published result stays available for late waiters. |
| `DIST_SF_POLL_INTERVAL_MS` | `100` | Waiter poll interval. Larger = less Redis load, more latency. Operators at scale often bump to 200-500. |
| `DIST_SF_POLL_TIMEOUT` | `30` (s) | Max block time before a waiter falls back to a direct upstream call. |

## Rolling back a bad release

Something regressed after you upgraded images? Try in order:

1. **Pin the previous tag.** Replace `:latest` with `:v<previous-release>` in each `image:` line of `docker-compose.yml`, then `docker compose pull && docker compose up -d`.
2. **Disable the suspected subsystem.** Add the relevant flag to the `backend` service's `environment:` block in `docker-compose.yml` (e.g. `- USE_INFORMER_CACHE=false`), then `docker compose up -d`. The backend falls back to direct K8s calls on every read — slower, but functional.
3. **Drop cache state.** `docker compose restart redis` clears the cache without touching persistent data. (Postgres and `backend-secrets` volumes are preserved.)

If none of that helps, open a bug report with `docker compose logs backend --tail 500`.
