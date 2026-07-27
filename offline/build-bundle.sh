#!/usr/bin/env bash
#
# Build the DFZ offline bundle for one architecture.
#
#   ./offline/build-bundle.sh --arch amd64 [--out dist]
#
# Run from an internet-connected machine (CI, normally). Produces
# dist/dfz-offline-<date>-<arch>.tar.gz plus a .sha256 next to it.
#
# The image list is READ FROM docker-compose.yml (`compose config --images`)
# rather than restated here. That is the whole point: a service added to the
# compose file is in the next bundle automatically, and a bundle can never ship
# a version different from the one the compose file pins. A hand-maintained
# list would be a second source of truth, and the one nobody remembers to edit.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH=""
OUT="$REPO/dist"

while [ $# -gt 0 ]; do
  case "$1" in
    --arch) shift; ARCH="${1:-}" ;;
    --out)  shift; OUT="${1:-}" ;;
    -h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

case "$ARCH" in
  amd64|arm64) ;;
  *) echo "--arch must be amd64 or arm64 (got '${ARCH:-}')" >&2; exit 1 ;;
esac

cd "$REPO"
DATE="$(date -u '+%Y.%m.%d')"
STAGE="$(mktemp -d)"
# The extracted directory carries the date so two bundles on one host stay
# apart. The TARBALL name deliberately does not: a stable filename is what makes
# .../releases/latest/download/dfz-offline-amd64.tar.gz a URL that keeps working,
# which matters when the download instructions are on paper in an air-gapped
# site. Which versions are inside is answered by VERSION and by the release.
NAME="dfz-offline-$DATE-$ARCH"
ASSET="dfz-offline-$ARCH.tar.gz"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Resolving the image list from docker-compose.yml"
# Unset the air-gap variables: the bundle must be built from the CANONICAL
# public references, whatever the builder happens to have exported.
IMAGES="$(env -u REGISTRY -u BASE_REGISTRY -u PULL_POLICY -u TAG \
  docker compose --profile monitoring --profile agent config --images | sort -u)"
[ -n "$IMAGES" ] || { echo "Resolved 0 images — compose config failed." >&2; exit 1; }
echo "$IMAGES" | sed 's/^/    /'

# install.sh maps each image to a target registry by its prefix (DFZ images
# follow REGISTRY, official ones follow BASE_REGISTRY). A service added from a
# third registry would build a bundle that only fails at the customer's mirror
# step — catch it here, where the person who added it is still looking.
for img in $IMAGES; do
  case "$img" in
    ghcr.io/devopsfromzero/*|docker.io/library/*) ;;
    *)
      echo "::error::$img is from a registry install.sh cannot map to a target." >&2
      echo "Add a prefix rule to target_for() in offline/install.sh first." >&2
      exit 1 ;;
  esac
done

echo "==> Pulling for linux/$ARCH"
# --platform on an amd64 runner still fetches the arm64 image; it is stored and
# saved fine, it just cannot be executed here. That is what lets one runner
# build both bundles.
for img in $IMAGES; do
  docker pull --quiet --platform "linux/$ARCH" "$img"
done

echo "==> Assembling $NAME"
mkdir -p "$STAGE/$NAME/images"
printf '%s\n' "$IMAGES" > "$STAGE/$NAME/images/manifest.txt"

version_of () {
  printf '%s\n' "$IMAGES" | sed -n "s#^ghcr.io/devopsfromzero/dfz-$1:##p" | head -n1
}

cat > "$STAGE/$NAME/VERSION" <<EOF
# DFZ offline bundle — sourced by install.sh.
BUNDLE_ARCH=$ARCH
BUNDLE_DATE=$DATE
BACKEND_VERSION=$(version_of backend)
UI_VERSION=$(version_of ui)
TERMINAL_VERSION=$(version_of terminal)
AGENT_VERSION=$(version_of agent)
GATEWAY_VERSION=$(version_of gateway)
EOF

cp docker-compose.yml Caddyfile "$STAGE/$NAME/"
cp offline/install.sh offline/config.env.example "$STAGE/$NAME/"
cp offline/README.md "$STAGE/$NAME/README.md"
chmod +x "$STAGE/$NAME/install.sh"

echo "==> Saving images (this is the slow part)"
# One save for all of them: shared base layers are stored once, which is worth
# several hundred MB across the two Python services.
# shellcheck disable=SC2086
docker save $IMAGES -o "$STAGE/$NAME/images/images.tar"

mkdir -p "$OUT"
echo "==> Compressing"
tar -C "$STAGE" -czf "$OUT/$ASSET" "$NAME"
( cd "$OUT" && sha256sum "$ASSET" > "$ASSET.sha256" )

SIZE="$(du -h "$OUT/$ASSET" | cut -f1)"
echo "==> $OUT/$ASSET  ($SIZE)  [extracts to $NAME/]"

# GitHub rejects a release asset over 2 GiB, and only after the whole upload has
# run. Fail here instead, where the message can say what to do about it.
BYTES="$(stat -c %s "$OUT/$ASSET" 2>/dev/null || stat -f %z "$OUT/$ASSET")"
if [ "$BYTES" -gt 2147483648 ]; then
  echo "::error::$ASSET is $SIZE — over GitHub's 2 GiB per-asset limit." >&2
  echo "Split it (split -b 1900M) or drop something from the bundle." >&2
  exit 1
fi
