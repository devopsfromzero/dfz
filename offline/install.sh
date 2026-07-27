#!/usr/bin/env bash
#
# DFZ offline installer — air-gapped / private-registry deployment.
#
# Everything this stack needs is inside the bundle you extracted: the images,
# the compose file, the edge config. Nothing is downloaded. Two ways to run it:
#
#   ./install.sh                 mirror mode — load the images, push them to
#                                YOUR registry, then start the stack.
#   ./install.sh --no-registry   local mode  — load the images and start the
#                                stack straight off the local daemon.
#
# Mirror mode is the one to use if you will connect Kubernetes clusters. A
# cluster pulls the agent image itself, and it cannot pull from this host's
# Docker daemon — it needs a registry it can reach. Local mode is complete for
# the dashboard, Docker hosts and kubeconfig-served clusters; --no-registry
# says so explicitly rather than letting you discover it at add-cluster time.
#
# Re-running is safe: loading, tagging, pushing and `compose up -d` are all
# idempotent, so a run interrupted halfway can simply be repeated.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# ── output ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_OFF=''
fi
step () { printf '\n%s==>%s %s\n' "$C_OK" "$C_OFF" "$*"; }
info () { printf '    %s\n' "$*"; }
dim  () { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
warn () { printf '%s[warn]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die  () { printf '%s[error]%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

usage () {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --no-registry     Skip the registry entirely; run from locally loaded images.
  --load-only       Load the images and stop. Nothing is pushed or started.
  --config FILE     Read settings from FILE (default: ./config.env).
  --dry-run         Print what would happen; change nothing.
  -h, --help        Show this help.

Settings come from config.env; any of them can also be passed as an
environment variable, which wins over the file.
EOF
}

# ── arguments ────────────────────────────────────────────────────────────────
MODE=registry
LOAD_ONLY=false
DRY_RUN=false
CONFIG_FILE="config.env"

while [ $# -gt 0 ]; do
  case "$1" in
    --no-registry) MODE=local ;;
    --load-only)   LOAD_ONLY=true ;;
    --dry-run)     DRY_RUN=true ;;
    --config)      shift; [ $# -gt 0 ] || die "--config needs a file path."; CONFIG_FILE="$1" ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1  (try --help)" ;;
  esac
  shift
done

run () {
  if [ "$DRY_RUN" = true ]; then dim "would run: $*"; else "$@"; fi
}

# ── configuration ────────────────────────────────────────────────────────────
# config.env is PARSED as literal KEY=VALUE, deliberately not `source`d.
#
# A Harbor robot account is named things like `robot$dfz`, and registry
# passwords routinely contain $, #, backticks or spaces. Sourcing expands and
# word-splits every one of those: under `set -u` the install dies with a
# baffling "dfz: unbound variable", and without it the credential is silently
# wrong and `docker login` just fails. Parsing also means a stray line in the
# file cannot overwrite PATH or anything else in this shell — only the six keys
# below are recognised.
FILE_REGISTRY=""; FILE_BASE_REGISTRY=""; FILE_REGISTRY_USERNAME=""
FILE_REGISTRY_PASSWORD=""; FILE_APP_URL=""; FILE_UI_PORT=""

read_settings () {
  local file="$1" line key value first last
  while IFS= read -r line || [ -n "$line" ]; do
    # Operators edit this on Windows and copy it to the air-gapped host more
    # often than not. A trailing CR would ride along into the password and make
    # `docker login` fail for a reason nothing on screen would explain.
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"; value="${line#*=}"
    key="${key#export }"
    key="${key%"${key##*[![:space:]]}"}"
    # One matching pair of surrounding quotes is stripped; anything else in the
    # value — including '#' — is kept verbatim.
    if [ ${#value} -ge 2 ]; then
      first="${value%"${value#?}"}"; last="${value#"${value%?}"}"
      if { [ "$first" = '"' ] && [ "$last" = '"' ]; } ||
         { [ "$first" = "'" ] && [ "$last" = "'" ]; }; then
        value="${value%?}"; value="${value#?}"
      fi
    fi
    case "$key" in
      REGISTRY)          FILE_REGISTRY="$value" ;;
      BASE_REGISTRY)     FILE_BASE_REGISTRY="$value" ;;
      REGISTRY_USERNAME) FILE_REGISTRY_USERNAME="$value" ;;
      REGISTRY_PASSWORD) FILE_REGISTRY_PASSWORD="$value" ;;
      APP_URL)           FILE_APP_URL="$value" ;;
      UI_PORT)           FILE_UI_PORT="$value" ;;
      *) warn "Ignoring unknown setting '$key' in $file." ;;
    esac
  done < "$file"
}

CONFIG_LOADED=false
if [ -f "$CONFIG_FILE" ]; then
  read_settings "$CONFIG_FILE"
  CONFIG_LOADED=true
elif [ "$MODE" = registry ] && [ "$LOAD_ONLY" = false ] && [ -z "${REGISTRY:-}" ]; then
  # --load-only never reaches the registry, so it must not demand one; that is
  # the flag people use to stage images on a host before deciding anything else.
  die "No $CONFIG_FILE and no REGISTRY set. Copy config.env.example to config.env and fill it in, or use --no-registry."
fi

# Environment wins over the file: CI and config-management tools should be able
# to pass a credential without writing it to disk.
REGISTRY="${REGISTRY:-$FILE_REGISTRY}"
BASE_REGISTRY="${BASE_REGISTRY:-$FILE_BASE_REGISTRY}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-$FILE_REGISTRY_USERNAME}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-$FILE_REGISTRY_PASSWORD}"
APP_URL="${APP_URL:-$FILE_APP_URL}"
UI_PORT="${UI_PORT:-${FILE_UI_PORT:-3080}}"

# Most sites mirror everything into one place, so the third-party registry
# follows the DFZ one unless it was set apart on purpose.
[ -n "$BASE_REGISTRY" ] || BASE_REGISTRY="$REGISTRY"

# Trailing slashes are the single most common paste error here and they produce
# a double slash in every image reference, which fails far from its cause.
REGISTRY="${REGISTRY%/}"
BASE_REGISTRY="${BASE_REGISTRY%/}"

# ── preflight ────────────────────────────────────────────────────────────────
step "Checking this host"

command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH."
docker info >/dev/null 2>&1 || die "Cannot talk to the Docker daemon. Is it running, and can this user reach it?"

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
  warn "Using the legacy docker-compose v1 binary. DFZ is tested on Compose v2.20+; upgrading is recommended."
else
  die "Docker Compose is not available (neither 'docker compose' nor 'docker-compose')."
fi
info "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?'), $("${COMPOSE[@]}" version --short 2>/dev/null || echo '?')"
[ "$CONFIG_LOADED" = false ] || info "Settings from $CONFIG_FILE"

[ -f VERSION ]              || die "VERSION is missing — is this the extracted bundle directory?"
[ -f docker-compose.yml ]   || die "docker-compose.yml is missing — is this the extracted bundle directory?"
[ -f images/images.tar ]    || die "images/images.tar is missing — the bundle is incomplete."
[ -f images/manifest.txt ]  || die "images/manifest.txt is missing — the bundle is incomplete."

# shellcheck disable=SC1091
. ./VERSION   # BUNDLE_ARCH, BUNDLE_DATE, and the per-component versions

case "$(uname -m)" in
  x86_64|amd64)  HOST_ARCH=amd64 ;;
  aarch64|arm64) HOST_ARCH=arm64 ;;
  *)             HOST_ARCH="$(uname -m)" ;;
esac
if [ "$HOST_ARCH" != "${BUNDLE_ARCH:-}" ]; then
  die "This is the ${BUNDLE_ARCH:-unknown} bundle but the host is $HOST_ARCH. Download the $HOST_ARCH bundle instead."
fi
info "Bundle ${BUNDLE_DATE:-?} for $BUNDLE_ARCH — backend ${BACKEND_VERSION:-?}, ui ${UI_VERSION:-?}, agent ${AGENT_VERSION:-?}"

# docker load needs room for the images on top of the tar already on disk.
TAR_KB=$(du -k images/images.tar | cut -f1)
FREE_KB=$(df -Pk . | awk 'NR==2 {print $4}')
NEED_KB=$(( TAR_KB * 2 ))
if [ "$FREE_KB" -lt "$NEED_KB" ]; then
  warn "Only $(( FREE_KB / 1024 )) MB free here; loading needs roughly $(( NEED_KB / 1024 )) MB. Free some space if the load fails."
fi

if [ "$LOAD_ONLY" = true ]; then
  info "Load-only run — nothing will be pushed or started."
elif [ "$MODE" = registry ]; then
  [ -n "$REGISTRY" ] || die "REGISTRY is empty. Set it in $CONFIG_FILE, or run with --no-registry."
  # The host[:port] is what `docker login` authenticates against — a repository
  # path underneath it is not part of the credential's scope.
  REGISTRY_HOST="${REGISTRY%%/*}"
  info "Mirroring into $REGISTRY (login host: $REGISTRY_HOST)"
  [ "$BASE_REGISTRY" = "$REGISTRY" ] || info "Third-party images go to $BASE_REGISTRY"
else
  info "Local mode — no registry will be contacted."
fi

# ── load ─────────────────────────────────────────────────────────────────────
step "Loading images into the local Docker daemon"
dim "$(wc -l < images/manifest.txt) images, $(( TAR_KB / 1024 )) MB — this takes a few minutes."
run docker load --input images/images.tar

if [ "$DRY_RUN" = false ]; then
  MISSING=""
  while read -r img; do
    [ -n "$img" ] || continue
    docker image inspect "$img" >/dev/null 2>&1 || MISSING="$MISSING  $img"$'\n'
  done < images/manifest.txt
  # A load that "succeeded" but left images missing means the tar and the
  # manifest disagree — a corrupt or hand-edited bundle. Say so now, rather
  # than letting `compose up` fail later with an unrelated-looking pull error.
  [ -z "$MISSING" ] || die $'These images are named in the manifest but were not loaded:\n'"$MISSING"
  info "All images present."
fi

if [ "$LOAD_ONLY" = true ]; then
  step "Done — images loaded (--load-only)."
  exit 0
fi

# ── mirror ───────────────────────────────────────────────────────────────────
# Where each image goes: the DFZ images follow REGISTRY, the third-party ones
# follow BASE_REGISTRY. This mirrors exactly how docker-compose.yml composes the
# two variables, so a pushed tag and the reference compose asks for cannot drift.
target_for () {
  case "$1" in
    ghcr.io/devopsfromzero/*) printf '%s/%s' "$REGISTRY" "${1#ghcr.io/devopsfromzero/}" ;;
    docker.io/library/*)      printf '%s/%s' "$BASE_REGISTRY" "${1#docker.io/library/}" ;;
    *) die "Don't know which registry $1 belongs to — the manifest and this script disagree." ;;
  esac
}

if [ "$MODE" = registry ]; then
  step "Pushing to $REGISTRY"

  if [ -n "$REGISTRY_USERNAME" ]; then
    # --password-stdin, never as an argument: anything on the command line is
    # visible in `ps` to every user on this host and lands in the shell history.
    if [ "$DRY_RUN" = true ]; then
      dim "would run: docker login $REGISTRY_HOST -u $REGISTRY_USERNAME --password-stdin"
    else
      [ -n "$REGISTRY_PASSWORD" ] || die "REGISTRY_USERNAME is set but REGISTRY_PASSWORD is empty."
      printf '%s' "$REGISTRY_PASSWORD" \
        | docker login "$REGISTRY_HOST" --username "$REGISTRY_USERNAME" --password-stdin \
        || die "docker login failed against $REGISTRY_HOST. Check the credentials, and that this host trusts the registry's TLS certificate."
      info "Logged in to $REGISTRY_HOST."
    fi
  else
    info "No REGISTRY_USERNAME set — assuming this host is already logged in (or the registry is open)."
  fi

  while read -r img; do
    [ -n "$img" ] || continue
    target="$(target_for "$img")"
    info "$img"
    dim  "  -> $target"
    run docker tag "$img" "$target"
    run docker push "$target" >/dev/null \
      || die "Pushing $target failed. Does the repository exist, and may this user write to it? (Harbor requires the project to exist first.)"
  done < images/manifest.txt

  info "All images mirrored."
fi

# ── configure ────────────────────────────────────────────────────────────────
# Compose reads .env from the project directory automatically, so writing it
# here is what makes every `docker compose` command in this directory — now and
# on every later upgrade or restart — use the mirrored registry.
step "Writing .env"

if [ "$MODE" = registry ]; then
  ENV_REGISTRY_LINE="REGISTRY=$REGISTRY"
  ENV_BASE_LINE="BASE_REGISTRY=$BASE_REGISTRY"
  # The images are already on this host, so there is nothing to pull. `missing`
  # also keeps a later `up -d` on a second host working off the registry.
  ENV_PULL="missing"
else
  # Deliberately left at the built-in defaults so the image references match the
  # tags that were just loaded.
  ENV_REGISTRY_LINE="# REGISTRY unset — running from the images loaded by install.sh"
  ENV_BASE_LINE="# BASE_REGISTRY unset — same reason"
  # `never` is the honest air-gap setting: a missing image fails immediately
  # with "image not found locally" instead of hanging on an unreachable registry.
  ENV_PULL="never"
fi

if [ "$DRY_RUN" = true ]; then
  dim "would write .env with $ENV_REGISTRY_LINE, PULL_POLICY=$ENV_PULL"
else
  # Registry credentials are deliberately NOT written here. Compose never needs
  # them (the images are local, and `docker login` already stored a token in
  # ~/.docker/config.json), and .env is world-readable in most deployments.
  cat > .env <<EOF
# Written by install.sh — DFZ offline install ($(date -u '+%Y-%m-%d %H:%M UTC')).
# Compose reads this automatically. Re-running install.sh rewrites it.
$ENV_REGISTRY_LINE
$ENV_BASE_LINE
PULL_POLICY=$ENV_PULL
EOF
  [ -z "$APP_URL" ] || printf 'APP_URL=%s\n' "$APP_URL" >> .env
  [ "$UI_PORT" = "3080" ] || printf 'UI_PORT=%s\n' "$UI_PORT" >> .env
  info "Wrote $(pwd)/.env"
fi

# ── start ────────────────────────────────────────────────────────────────────
step "Starting DFZ"
run "${COMPOSE[@]}" up -d

if [ "$DRY_RUN" = true ]; then
  step "Dry run complete — nothing was changed."
  exit 0
fi

# The backend runs schema migrations on first boot, so the wait is real rather
# than cosmetic. Report the truth on timeout instead of claiming success.
step "Waiting for the stack to come up"
DEADLINE=$(( $(date +%s) + 300 ))
while :; do
  UNHEALTHY=""
  for c in dfz-postgres dfz-backend dfz-ui dfz-caddy; do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c" 2>/dev/null || echo missing)"
    case "$status" in
      healthy|running) ;;
      *) UNHEALTHY="$UNHEALTHY $c($status)" ;;
    esac
  done
  [ -n "$UNHEALTHY" ] || break
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    warn "Still not healthy after 5 minutes:$UNHEALTHY"
    warn "The stack is running — check '${COMPOSE[*]} logs backend --tail 100'. First boot runs migrations and can be slow on modest hardware."
    exit 1
  fi
  sleep 5
done

URL="${APP_URL:-http://localhost:$UI_PORT}"
step "DFZ is up — open $URL"
info "You will be asked to create the admin account on first open; there is no default password."

if [ "$MODE" = local ]; then
  printf '\n'
  warn "Local mode: in-cluster Kubernetes agents will NOT work yet."
  info "A cluster pulls the agent image itself and cannot reach this host's Docker daemon."
  info "To connect clusters, push the agent image to a registry your clusters can reach:"
  info "  docker tag  ghcr.io/devopsfromzero/dfz-agent:${AGENT_VERSION:-latest} <your-registry>/dfz-agent:${AGENT_VERSION:-latest}"
  info "  docker push <your-registry>/dfz-agent:${AGENT_VERSION:-latest}"
  info "Then set that registry in Settings -> Security -> Container registry, so every"
  info "add-cluster wizard offers the mirrored image by default."
  info "Clusters reachable from this host by kubeconfig work now, with no registry."
fi

if [ -n "$REGISTRY_PASSWORD" ] && [ -f "$CONFIG_FILE" ] && grep -q '^[[:space:]]*REGISTRY_PASSWORD=..' "$CONFIG_FILE" 2>/dev/null; then
  printf '\n'
  warn "$CONFIG_FILE still holds your registry password. Delete or blank it now — the install no longer needs it."
fi
