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

## Cluster agents & collection

Every cluster is served by a dfz-agent — the hub never dials a cluster's API
server itself. The agent runs in one of two places:

- **In-cluster** (production): deployed inside each cluster via the add-cluster
  wizard's manifest; it dials out to this stack over the `/agent-tunnel`
  websocket (via the Caddy edge).
- **Local kubeconfig** (bundled `local-agent` service): serves every context of
  a kubeconfig you mount — no in-cluster install. See the next section.

Either way, the stack derives its analytics (risk, waste, topology, dashboard)
from what the agent collects. The related knobs (all already defaulted in
`docker-compose.yml`):

| Variable | Default | Where | Notes |
|----------|---------|-------|-------|
| `DFZ_AGENT_SERVER_URL` | `${APP_URL}` | `x-app-env` | URL the add-cluster wizard bakes into agent manifests — agents dial this for heartbeat + tunnel. Must be reachable **from the clusters**; set `APP_URL` when not on localhost. |
| `DFZ_AGENT_IMAGE` | the agent version this bundle pins (see `x-app-env` in `docker-compose.yml`) | `x-app-env` | Agent image the add-cluster wizard hands to each managed cluster. Pinned by default, so cluster rollouts are reproducible; override it to move a fleet independently of the bundle. |
| `DFZ_GATEWAY_PROXY_URL` | `http://gateway:3092` | `x-app-env` + `terminal` | Internal gateway proxy the backend/terminal use to reach each agent's apiserver through its tunnel. Only change for a split deployment. |
| `DFZ_COLLECTION_SYNC_INTERVAL` | `60` (s) | `x-app-env` | Cadence at which the worker pulls each agent's usage/events windows into PostgreSQL. Load-tuned floor: raise it on very large fleets; do **not** lower it. |
| `DFZ_GATEWAY_DEV_INSECURE` | `0` | `gateway` | Escape hatch that skips agent-token validation against the backend. Lab-only; keep `0` in production. |
| `BACKEND_RUN_JOBS` | `false` | `backend` | Set `true` (and remove the `worker` service) for a single-container deploy that runs background jobs in the API process. |
| `DFZ_HEARTBEAT_INTERVAL` | `30` (s) | agent (in-cluster) | How often each agent reports home; the UI marks a tunnel agent stale after ~120 s without one. |

## Local clusters from a kubeconfig (bundled local-agent)

For clusters your host can already reach (an on-prem RKE2/k3s, a VM lab, a
remote dev cluster), you don't need an in-cluster install:

1. Put the kubeconfig at `./kubeconfig/config` (the directory is created on
   first `up`). It is **one file, any number of contexts** — every context
   becomes its own cluster. To serve several separate kubeconfig files, merge
   them into that one file first:

   ```bash
   # Linux/macOS
   KUBECONFIG=cluster-a.yaml:cluster-b.yaml:cluster-c.yaml \
     kubectl config view --flatten > kubeconfig/config
   ```
   ```powershell
   # Windows (PowerShell)
   $env:KUBECONFIG = "cluster-a.yaml;cluster-b.yaml;cluster-c.yaml"
   kubectl config view --flatten | Out-File -Encoding ascii kubeconfig\config
   ```
2. `docker compose restart local-agent worker`
3. Every context appears as a cluster in the UI, served by the `local-agent`
   service. Contexts are lazy — a cluster is only watched once someone views it,
   and its cache is evicted again after `DFZ_AGENT_IDLE_EVICT_MINUTES`.

The kubeconfig **file is the source of truth**: add a context and restart to add
a cluster, remove one and the cluster is dropped on the next worker start. The
file stays on your host — the hub database stores no cluster credentials; only
the local-agent reads them.

Limits and notes:

- **EKS/GKE default kubeconfigs won't work here** — they authenticate through an
  exec plugin (`aws` / `gke-gcloud-auth-plugin`) that the agent image does not
  ship. Connect those clusters with the in-cluster agent; the API returns a
  clear error message if you try. Client-cert and static-token kubeconfigs
  (RKE2, k3s, kubeadm, Rancher) work as-is.
- A kubeconfig whose server is `127.0.0.1` (kind, minikube on this host) is
  unreachable from inside the container — edit the server to
  `host.docker.internal` (resolvable in the `local-agent` container).

| Variable | Default | Where | Notes |
|----------|---------|-------|-------|
| `KUBECONFIG_DIR` | `./kubeconfig` | `backend` + `worker` + `local-agent` | Host directory mounted read-only at `/kubeconfig`; the file inside must be named `config`. |
| `DFZ_AGENT_IDLE_EVICT_MINUTES` | `15` | `local-agent` | Evict an unviewed cluster's watchers + cache after this long; `0` disables eviction. |
| `DFZ_LOCAL_AGENT_TOKEN` | auto-generated | `x-app-env` + `local-agent` | Shared backend↔local-agent secret. `token-init` generates one into a volume on first run; set this only to pin your own. |
| `DFZ_AGENT_REQUIRE_AUTH` | `true` | `local-agent` | Keep `true`: the local agent rejects requests without the shared token. |

### Storing credentials in the hub instead of the file (opt-in)

By default the local-agent reads the shared `./kubeconfig/config` file (above). Two
opt-in flags change *where the credential lives* and *whose credential it is* —
both **default off**, so leaving them unset keeps the file-drop behaviour exactly.

- **`DFZ_CREDENTIALS_FROM_HUB=true`** — an On-Premises **upload** in the UI is split
  into one vault-encrypted record per context in PostgreSQL, and the local-agent
  fetches each cluster's credentials from the hub at request time instead of a
  shared file. Content-based onboarding: paste/upload the kubeconfig and the
  clusters appear, with nothing dropped on disk. (Exec-plugin contexts are still
  skipped, same as the file path.) The local-agent needs to reach the hub, so it
  also needs `DFZ_SERVER_URL`.

- **`DFZ_DERIVE_SA=true`** (builds on the above) — the first time the agent opens
  such a cluster it uses your uploaded credential **once** to create its own
  ServiceAccount in the target cluster (`dfz-system/dfz-agent-manager`, bound to
  `cluster-admin`) plus a long-lived token, reports the token to the hub, and the
  hub then keeps **only** that token — your uploaded credential is overwritten. So
  DFZ stops holding your kubeconfig credential; you can rotate it freely. If the
  uploaded credential lacks the RBAC to create the SA, the agent logs the reason
  and keeps working with your credential (the cluster is never broken). The
  profile list shows the credential state (`Managed SA` / `Deriving SA…`).
  *Deleting the cluster removes the hub record but does not remove the derived SA
  from the target cluster* — clean it up with `kubectl delete sa dfz-agent-manager
  -n dfz-system` (+ its ClusterRoleBinding) if you want it gone.

To enable, add the lines to the `environment:` blocks that read them and
`docker compose up -d`:

```yaml
  # backend AND worker (they share the x-app-env anchor — add once there):
  DFZ_CREDENTIALS_FROM_HUB: "true"
  DFZ_DERIVE_SA: "true"           # optional; omit for hub-stored-credential only
```
```yaml
  # local-agent service `environment:` list:
      - DFZ_CREDENTIALS_FROM_HUB=true
      - DFZ_SERVER_URL=http://backend:8000
```

| Variable | Default | Where | Notes |
|----------|---------|-------|-------|
| `DFZ_CREDENTIALS_FROM_HUB` | `false` | `x-app-env` (backend+worker) + `local-agent` | Store uploaded credentials as per-cluster encrypted PG records; the agent fetches them from the hub. Composes with the file path (agent falls back to the kubeconfig on a miss). |
| `DFZ_DERIVE_SA` | `false` | `x-app-env` (backend+worker) | Derive DFZ's own cluster-admin ServiceAccount once and discard the uploaded credential. Requires `DFZ_CREDENTIALS_FROM_HUB`. |
| `DFZ_SERVER_URL` | — | `local-agent` | How the agent reaches the hub for the credential fetch; `http://backend:8000` in this stack. Required when `DFZ_CREDENTIALS_FROM_HUB=true`. |

## Windows host monitoring (WinRM)

VM monitoring collects Windows hosts agentlessly over WinRM (default port 5985). Authentication is Negotiate: **Kerberos** for domain-joined hosts, **NTLM** for workgroup hosts or hosts added by IP address.

### Adding a domain host

For Kerberos to engage, all three of these must hold — otherwise Negotiate silently falls back to NTLM, which fails on NTLM-hardened domains:

| Requirement | Detail |
|-------------|--------|
| Host added by **FQDN** | `srv01.corp.example`, not an IP — Kerberos tickets are issued per service FQDN. |
| Username as **UPN** | `svc-monitor@corp.example`. Realm casing is normalized automatically. |
| Backend can resolve **AD DNS** | KDC discovery uses DNS SRV records. Give the `backend` **and** `worker` services a `dns:` entry pointing at a domain controller — put it in a local `docker-compose.override.yml` (auto-loaded by compose) rather than editing the bundle, e.g. `services: { backend: { dns: [10.0.0.10] }, worker: { dns: [10.0.0.10] } }`. **Or** mount your own `krb5.conf` and set `KRB5_CONFIG` on both services. |

Verified against a domain with incoming NTLM fully disabled (`Network security: Restrict NTLM: Deny all`) — the connection authenticates with Kerberos end to end.

### Least-privilege monitoring account

A domain monitoring account does **not** need local Administrator. The verified minimal set on each monitored host:

| Grant | Where | Why |
|-------|-------|-----|
| Member of `Remote Management Users` | Local group on the host | Allows the WinRM connection itself. |
| `Enable Account` + `Remote Enable` | WMI ACL on the `root/cimv2` namespace (apply to subnamespaces) | The collector reads CIM classes (`Win32_OperatingSystem`, `Win32_PerfRawData_*`, `Win32_LogicalDisk`, …). A WinRM session is a network logon, and the default WMI ACL lacks `Remote Enable` for non-admins — this is the bit that unblocks it. |
| Member of `Performance Log Users` | Local group on the host | Without it the `Win32_PerfRawData_*` performance classes return **empty result sets** to a non-admin — no error, just zero rows — so CPU, network and disk-I/O rates silently stay blank while memory/disk/system info keep working. |

Explicitly **not** required (verified by removing them): local `Administrators`, `Performance Monitor Users`, `Distributed COM Users`.

Grant the WMI ACL once per host as an administrator (replace the account):

```powershell
$sid = (New-Object System.Security.Principal.NTAccount('CORP\svc-monitor')).Translate([System.Security.Principal.SecurityIdentifier]).Value
$inv = @{Namespace='root/cimv2'; Path='__systemsecurity=@'}
$sd  = (Invoke-WmiMethod @inv -Name GetSecurityDescriptor).Descriptor
$ace = (New-Object System.Management.ManagementClass('win32_Ace')).CreateInstance()
$ace.AccessMask = 0x21   # Enable Account (0x1) + Remote Enable (0x20)
$ace.AceFlags   = 0x2    # inherit to subnamespaces
$ace.AceType    = 0x0
$tr  = (New-Object System.Management.ManagementClass('win32_Trustee')).CreateInstance()
$tr.SidString = $sid
$ace.Trustee  = $tr
$sd.DACL += $ace.PSObject.ImmediateBaseObject
(Invoke-WmiMethod @inv -Name SetSecurityDescriptor -ArgumentList $sd.PSObject.ImmediateBaseObject).ReturnValue  # 0 = success
net localgroup "Remote Management Users" "CORP\svc-monitor" /add
net localgroup "Performance Log Users" "CORP\svc-monitor" /add
```

The **Restart** host action is the one exception: it runs `shutdown /r`, which the least-privilege set does not allow. Use an admin account for that host, or grant the account shutdown rights, if you need restarts from the console.

## Rolling back a bad release

Something regressed after you upgraded images? Try in order:

1. **Roll the whole bundle back.** Every commit of this repo pins an image set that was tested together, so `git checkout <earlier-commit> && docker compose up -d` puts you back on that exact stack — compose file, edge config and pins included. `git log --oneline -- docker-compose.yml` lists the commits where the pins moved.
2. **Roll back a single component.** Components version independently, so use its per-service tag variable, e.g. `BACKEND_TAG=v2.4.1 docker compose up -d` to move only the backend (each of `BACKEND_TAG / UI_TAG / TERMINAL_TAG / AGENT_TAG / GATEWAY_TAG` falls back to `TAG`, then to the version this bundle pins).
3. **Disable the suspected subsystem.** Add the relevant flag to the `backend` service's `environment:` block in `docker-compose.yml` (e.g. `- USE_INFORMER_CACHE=false`), then `docker compose up -d`. The backend falls back to direct K8s calls on every read — slower, but functional.
4. **Drop cache state.** `docker compose restart redis` clears the cache without touching persistent data. (Postgres and `backend-secrets` volumes are preserved.)

If none of that helps, open a bug report with `docker compose logs backend --tail 500`.
