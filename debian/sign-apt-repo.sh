#!/bin/sh
# Signs every file under the staged apt-repo/*/ trees that apt-cosign-method
# will independently verify - InRelease, Packages, and each .deb; it has no
# special case for "this one is the trust anchor", so each needs its own
# apt-cosign-sign bundle. Run after debian/build-apt-repo.sh.
#
# Needs a real OIDC identity: GitHub Actions' ambient token (in a job with
# `permissions: id-token: write`) is what the workflow uses - see
# apt-cosign-sign -h for other options. Runs natively, not in a container -
# the ambient OIDC env vars GitHub sets on the job aren't forwarded into a
# container docker compose run would spin up.
set -eu

cd "$(dirname "$0")/.."

SIGN_BIN=${APT_COSIGN_SIGN:-./apt-cosign-sign}
[ -x "$SIGN_BIN" ] || { echo "sign-apt-repo.sh: $SIGN_BIN missing or not executable" >&2; exit 1; }

REPO_DIR=apt-repo
[ -d "$REPO_DIR" ] || { echo "sign-apt-repo.sh: $REPO_DIR missing; run debian/build-apt-repo.sh first" >&2; exit 1; }

find "$REPO_DIR" -type f \( -name InRelease -o -name Packages -o -name '*.deb' \) | sort | while read -r f; do
  echo "signing $f"
  "$SIGN_BIN" "$@" "$f"
done
