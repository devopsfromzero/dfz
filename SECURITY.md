# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in DFZ, please report it privately — **do not open a public issue**.

Use GitHub's private Security Advisory to submit the report:

👉 **https://github.com/devopsfromzero/dfz/security/advisories/new**

Please include:
- A description of the issue
- Steps to reproduce
- The affected version / tag
- Any known mitigation

### Response expectations

- Acknowledgement within **3 business days**
- Initial assessment within **7 days**
- Fix target: critical issues prioritized over a single release cycle; non-critical fixes bundled into the next planned release

## Supported Versions

Only the most recent release receives security fixes. Older versions (including images pinned via the `TAG` environment variable) may require an upgrade to receive patches.

| Version | Supported |
|---------|-----------|
| `latest` (tracking main) | ✅ |
| Most recent `vX.Y.Z` tag  | ✅ |
| Older tags | ❌ (upgrade required) |

## Scope

**In scope**
- Vulnerabilities in the packaged container images (`ghcr.io/devopsfromzero/dfz-*`)
- The `docker-compose.yml` in this repository, including its embedded defaults

**Out of scope**
- User-provided overrides (custom `docker-compose.yml` edits, reverse proxy config, TLS termination)
- Third-party images pinned in `docker-compose.yml` (postgres, redis) — report upstream
- Brute-force / rate-limit issues against deployments exposed without a reverse proxy (deploy behind one)
