#!/bin/sh
# Stages a flat-format apt repo (no dists/ hierarchy: `deb URL/ ./`) per OS
# release, from the .debs the build matrix already produced into dist/. One
# release's .deb can't share a single flat repo with another release's: same
# Package/Version, different bytes, and a flat Packages file has no
# per-codename axis to key on - so each codename gets its own subdirectory,
# each independently a complete little repo (own Packages, own InRelease).
# See non7top/apt-cosign's README ("Hosting a repo on
# raw.githubusercontent.com") for the mechanism this borrows.
set -eu

cd "$(dirname "$0")/.."

[ -n "$(find dist -maxdepth 1 -name '*.deb' -print -quit)" ] || {
  echo "build-apt-repo.sh: no .deb in dist/; download the build matrix's artifacts into dist/ first" >&2
  exit 1
}

REPO_DIR=apt-repo
rm -rf "$REPO_DIR"

for deb in dist/*.deb; do
  base=$(basename "$deb" .deb)
  # nginx-module-vts_<version>_<codename>_amd64 -> <codename>
  codename=$(echo "${base%_amd64}" | sed -E 's/.*_//')

  dir="$REPO_DIR/$codename"
  mkdir -p "$dir"
  cp "$deb" "$dir/"
done

for dir in "$REPO_DIR"/*/; do
  codename=$(basename "$dir")
  (
    cd "$dir"
    # dpkg-scanpackages needs an override file argument; /dev/null means "no
    # overrides". Filename entries come out relative to "." (e.g.
    # "./nginx-module-vts_0.2.7-1_jammy_amd64.deb"), which apt resolves
    # against the repo's own base URI.
    dpkg-scanpackages . /dev/null > Packages

    packages_sha256=$(sha256sum Packages | cut -d' ' -f1)
    packages_size=$(wc -c < Packages)

    cat > InRelease <<EOF
Origin: nginx-modules
Label: nginx-modules
Suite: stable
Codename: ${codename}
Architectures: amd64
Components: main
Description: nginx-module-vts prebuilt repo for Ubuntu ${codename} (sigstore-verified, no GPG signature - see README)
Date: $(date -u -R)
SHA256:
 ${packages_sha256} ${packages_size} Packages
EOF
  )
  echo "staged $dir ($(find "$dir" -maxdepth 1 -name '*.deb' | wc -l) .deb, Packages, InRelease)"
done
