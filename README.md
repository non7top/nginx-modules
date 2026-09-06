# nginx-modules

Prebuilt nginx dynamic modules for the wr0.ru fleet (jammy/22.04, noble/24.04, resolute/26.04), built via GitHub Actions and published as GitHub Release assets. Consumed by [non7top/wr-salt-new](https://github.com/non7top/wr-salt-new) (`ispconfig3/vts.sls`), which pins each module's exact release asset by sha256 rather than compiling it on production nodes.

## Why this exists

Compiling a module on every node it's deployed to works, but repeats the same build on every server instead of once, and requires a full build toolchain (`build-essential`, dev libraries, and for jammy a pinned nginx source tarball) installed on production infrastructure just to produce one `.so` file. Building once here and downloading a hash-pinned, signed artifact avoids both.

## How a module gets built

Each module has its own workflow (currently just `nginx-module-vts`), triggered manually (`workflow_dispatch`) with the upstream module's git tag to build. It's matrixed across the three OS releases the fleet actually runs, using the same build mechanism as the consuming Salt state does when it *does* still compile locally on a fresh clone:

- **jammy**: no `nginx-dev` package exists for it, so it builds against nginx.org's own upstream source (version-pinned + hash-verified) with `--with-compat`, relying on that flag's ABI-compatibility guarantee with the distro-patched binary.
- **noble/resolute**: uses the `nginx-dev` package, which ships the exact matching nginx source tree plus the real build's own configure flags (`conf_flags`) - so the module always matches whatever `nginx-core` is actually installed on that release, with no separate version to track.

## Verifying a release

Every `.so` has a matching `.cosign.bundle` - a keyless Sigstore signature bound to this repo's own GitHub Actions workflow identity (no private key involved). Verify with:

```
cosign verify-blob --bundle FILE.so.cosign.bundle \
  --certificate-identity-regexp 'https://github.com/non7top/nginx-modules/.github/workflows/build-nginx-vts.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  FILE.so
```
