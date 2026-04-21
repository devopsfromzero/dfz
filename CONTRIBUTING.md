# Contributing to DFZ

Thanks for your interest! This repository ships **deployment manifests** — the `docker-compose.yml`, `.env.example`, docs, and community files. The application source code is maintained privately and published only as container images on `ghcr.io/devopsfromzero`.

## What you can contribute here

- **Bug reports** — issues with the deploy stack (compose errors, missing env vars, documentation gaps)
- **Feature requests** — new environment variables, compose override profiles, documentation improvements
- **Deployment profiles** — alternate `docker-compose.*.yml` files for common setups (behind Traefik, external PostgreSQL, Kubernetes via Kompose)
- **Translations** — README translations into other languages

> 🔒 **Application bugs** (UI glitches, backend errors, K8s resource handling): file an issue here — we will triage and forward upstream to the private source repository where needed.

## Reporting bugs

Use the **Bug report** issue template. Include:

- Exact command or URL that failed
- `docker compose ps` output
- Relevant log excerpts:
  ```bash
  docker compose logs backend --tail 100
  docker compose logs ui --tail 100
  ```
- Your `docker --version` and `docker compose version`
- The image tag you're running (`TAG` in `.env`, or `latest`)

## Submitting changes

1. Fork the repository
2. Create a branch:
   - `fix/...` for bug fixes
   - `docs/...` for documentation
   - `feat/...` for new features (e.g. override profiles)
3. Make your change; keep commits focused
4. Open a pull request against `main`
5. Fill out the PR template (what, why, how tested)

### Before submitting

- [ ] `docker compose config` succeeds (no YAML errors)
- [ ] `docker compose up -d` works end-to-end on a fresh environment
- [ ] README / `.env.example` updated if you added or changed env variables
- [ ] No secrets committed (checked with `git diff --staged`)

## Cross-cutting changes

Changes that affect the application image contract (new env variables the backend expects, new ports, new volumes) need to be coordinated with the upstream source repository. Open an issue first describing what you want to do; we will confirm whether the image side can support it before you invest time in the deploy-side change.

## Code of Conduct

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Security vulnerabilities

See [SECURITY.md](SECURITY.md) — report privately, **never** in a public issue.
