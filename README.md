# nginx-modules

Prebuilt nginx dynamic modules for the wr0.ru fleet (jammy/22.04, noble/24.04, resolute/26.04), packaged as real `.deb`s and built via GitHub Actions. Consumed by [non7top/wr-salt-new](https://github.com/non7top/wr-salt-new) (`ispconfig3/vts.sls`), which downloads each release's `.deb` directly (pinned by sha256) and installs it via Salt's `pkg.installed`. A real apt repo is also published per release (see "Installing via apt" below), for anything that would rather add a source and run `apt-get install` than track sha256 pins by hand.

## Why this exists

Compiling a module on every node it's deployed to works, but repeats the same build on every server instead of once, and requires a full build toolchain (`build-essential`, dev libraries, and for jammy a pinned nginx source tarball) installed on production infrastructure just to produce one package. Building once here and installing a hash-pinned, signed `.deb` avoids both.

## How a module gets built

Each module has its own workflow (currently just `nginx-module-vts`), triggered manually (`workflow_dispatch`) with the upstream module's git tag and a package revision to build. It's matrixed across the three OS releases the fleet actually runs, using the same build mechanism as the consuming Salt state does when it *does* still compile locally on a fresh clone:

- **jammy**: no `nginx-dev` package exists for it, so it builds against nginx.org's own upstream source (version-pinned + hash-verified) with `--with-compat`, relying on that flag's ABI-compatibility guarantee with the distro-patched binary.
- **noble/resolute**: uses the `nginx-dev` package, which ships the exact matching nginx source tree plus the real build's own configure flags (`conf_flags`) - so the module always matches whatever `nginx-core` is actually installed on that release, with no separate version to track.

The built `.so` is packaged directly with `dpkg-deb --build` (confirmed installable via `dpkg -i`/`apt remove`, shows correctly in `dpkg -l`) rather than through nginx's own `nginx_mod` debhelper buildsystem - that expects the module source to ship its own `debian/` packaging, which `vozlt/nginx-module-vts` doesn't. The module goes straight into `/etc/nginx/modules-enabled/` rather than the available+enabled symlink split real distro module packages use - that split exists so a module can be disabled without uninstalling it, which nothing here needs.

## Verifying a release

Every `.deb` has a matching `.cosign.bundle` - a keyless Sigstore signature bound to this repo's own GitHub Actions workflow identity (no private key involved). Verify with:

```
cosign verify-blob --bundle FILE.deb.cosign.bundle \
  --certificate-identity-regexp 'https://github.com/non7top/nginx-modules/.github/workflows/build-nginx-vts.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  FILE.deb
```

## Installing via apt

Every release also publishes a real, flat apt repo (`deb URL/ ./`, no
`dists/` hierarchy) on the `apt-repo` branch - built and signed the same way
[non7top/apt-cosign](https://github.com/non7top/apt-cosign) publishes its own
demo repo, using that project's `apt-cosign-sign` instead of raw `cosign
sign-blob`. Because jammy/noble/resolute builds of the same version aren't
byte-identical (different nginx source, different `Depends`), they can't
share one flat Packages index - each codename gets its own subdirectory,
independently a complete repo:

```
deb [trusted=yes] sigstore+https://raw.githubusercontent.com/non7top/nginx-modules/refs/heads/apt-repo/<jammy|noble|resolute>/ ./
```

This needs [apt-cosign](https://github.com/non7top/apt-cosign) installed
first (`sigstore+https` isn't a scheme apt understands on its own), and a
policy configured to accept this repo's own build workflow identity:

```
Acquire::sigstore::Enforce::Repo::Owner "non7top";
Acquire::sigstore::Enforce::Repo::Name "nginx-modules";
Acquire::sigstore::Enforce::Repo::Pipeline "build-nginx-vts.yml";
```

`[trusted=yes]` tells apt to skip its own GPG check - there's no
`Release.gpg` or inline-signed `InRelease` here, the sigstore bundle
`apt-cosign-method` fetches alongside each file *is* the trust mechanism.
