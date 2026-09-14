#!/usr/bin/env bash
# Tests for install.sh's decision logic. No Docker daemon, no images, no network:
# every case here is about which MODE the installer picks and whether it refuses
# to start.
#
# WHY THIS FILE EXISTS
# An upgrade of a --no-registry install was impossible through the documented
# path. README says the upgrade is:
#
#     ./install.sh --status
#     ./install.sh
#
# but plain `./install.sh` defaults to MODE=registry, found no config.env, and
# died with "No config.env and no REGISTRY set." on every air-gapped host — the
# exact machines that deliberately have no registry. It was reproduced on a real
# air-gapped VM upgrading v2.21.1 -> v2.22.0 before it was fixed.
#
# The record needed to decide was already on disk: the .env that install.sh
# itself writes. Local mode is the only mode that sets PULL_POLICY=never AND
# leaves REGISTRY unset. These tests pin that reading down.
#
# Usage:  offline/install-test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$HERE/install.sh"
[ -f "$INSTALL" ] || { echo "install.sh not found next to this test"; exit 2; }

pass=0
fail=0
ok   () { pass=$((pass+1)); printf 'ok    %s\n' "$*"; }
bad  () { fail=$((fail+1)); printf 'FAIL  %s\n' "$*"; }

# ── the mode-detection helper, tested directly ───────────────────────────────
# Pulled out of install.sh rather than copied, so the test cannot drift from the
# code it checks.
FN="$(mktemp)"
sed -n '/^previous_install_was_local () {/,/^}/p' "$INSTALL" > "$FN"
# Positive control: if the extraction returned nothing, every "not local"
# expectation below would be satisfied by "command not found" and the whole
# block would pass while testing nothing.
if [ ! -s "$FN" ]; then
  echo "FAIL  could not extract previous_install_was_local from install.sh"
  exit 1
fi
# shellcheck source=/dev/null
. "$FN"
type previous_install_was_local >/dev/null 2>&1 \
  || { echo "FAIL  previous_install_was_local did not load"; exit 1; }
ok "helper extracted and loaded (positive control)"

case_env () {  # case_env <name> <expect 0=local|1=not> <.env contents|NONE>
  local name="$1" want="$2" body="$3" dir got
  dir="$(mktemp -d)"
  ( cd "$dir"
    [ "$body" = NONE ] || printf '%s\n' "$body" > .env
    previous_install_was_local )
  got=$?
  [ "$got" = "$want" ] && ok "$name" || bad "$name (want $want, got $got)"
  rm -rf "$dir"
}

case_env "local-mode .env is recognised"          0 "$(printf '# REGISTRY unset\nPULL_POLICY=never')"
case_env "registry-mode .env is not local"        1 "$(printf 'REGISTRY=harbor.example/dfz\nPULL_POLICY=missing')"
case_env "no .env at all is not local"            1 NONE
case_env "PULL_POLICY=missing alone is not local" 1 "PULL_POLICY=missing"
case_env "commented REGISTRY does not mislead"    0 "$(printf '# REGISTRY unset - running from loaded images\nPULL_POLICY=never')"
case_env "REGISTRY set wins over never"           1 "$(printf 'REGISTRY=r.example\nPULL_POLICY=never')"

# ── the defect itself: the documented upgrade must not be refused ────────────
# Runs the real script. It will not get far without images, and that is fine —
# what is asserted is that it does NOT stop at the config gate.
GATE='No config.env and no REGISTRY set'

# install.sh cd's to its OWN directory on line 2, so a sandbox with an .env is
# invisible unless the script is copied INTO it. The first version of this test
# missed that and both cases below passed while measuring nothing.
sandbox () {  # sandbox <dir> -> a runnable copy of install.sh inside it
  cp "$INSTALL" "$1/install.sh"
  chmod +x "$1/install.sh"
}

refuses () {  # refuses <dir> -> 0 when install.sh stopped at the config gate
  # Output is captured BEFORE grepping, deliberately. Piping install.sh straight
  # into grep looks equivalent but is not: under `set -o pipefail` the die()
  # exit status outranks grep's, so the pipeline reports "no match" whenever the
  # installer exits non-zero -- which is exactly the case being detected. The
  # first version of this test did that and BOTH cases below were unreliable.
  local out
  out="$( cd "$1" && ./install.sh --dry-run 2>&1 || true )"
  printf '%s' "$out" | grep -q "$GATE"
}

dir="$(mktemp -d)"
sandbox "$dir"
printf '# REGISTRY unset\nPULL_POLICY=never\n' > "$dir/.env"
if refuses "$dir"; then
  bad "plain ./install.sh on a local-mode install is refused (the shipped defect)"
else
  ok "plain ./install.sh continues on a local-mode install"
fi
rm -rf "$dir"

# Counter-check: a directory with NO .env is a fresh install with no registry
# named anywhere, and must still be refused — otherwise the fix above would have
# simply removed the guard.
dir="$(mktemp -d)"
sandbox "$dir"
if refuses "$dir"; then
  ok "fresh install with no config and no .env is still refused"
else
  bad "guard is gone: fresh install without a registry was allowed through"
fi
rm -rf "$dir"

# ── the upgrade promise: the archive must not carry operator files ───────────
# Both READMEs tell people to extract the new bundle OVER the directory they
# installed from, and say their own files survive because the archive does not
# contain them. That is a promise about build-bundle.sh, and it is the kind that
# breaks quietly: adding one `cp .env` there would make every upgrade overwrite
# the operator's configuration, and nothing would fail — it would just be gone.
BUILDER="$HERE/build-bundle.sh"
[ -f "$BUILDER" ] || { echo "FAIL  build-bundle.sh not found"; exit 1; }

# What the builder actually stages, read from the file rather than assumed.
staged="$(grep -E '^\s*cp .*"\$STAGE' "$BUILDER")"
# Positive control: an empty scan would let every assertion below pass.
[ -n "$staged" ] || { echo "FAIL  found no staging 'cp' lines — the scan is broken"; exit 1; }
ok "builder staging lines found (positive control)"

for f in '.env' 'config.env' 'backups'; do
  # config.env.example is a template and belongs in the archive; config.env is
  # the operator's filled-in copy and must never be.
  if printf '%s\n' "$staged" | grep -E "(^|[^.a-zA-Z0-9_-])$f([^.a-zA-Z0-9_-]|$)" \
       | grep -qv 'config.env.example'; then
    bad "build-bundle.sh stages '$f' — an upgrade would overwrite it"
  else
    ok "archive does not carry '$f'"
  fi
done

rm -f "$FN"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
