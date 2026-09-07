# nginx-modules

Prebuilt nginx dynamic modules for the wr0.ru fleet (jammy/22.04, noble/24.04, resolute/26.04), packaged as real `.deb`s and built via GitHub Actions. Consumed by [non7top/wr-salt-new](https://github.com/non7top/wr-salt-new) (`ispconfig3/vts.sls`), which downloads each release's `.deb` directly (pinned by sha256) and installs it via Salt's `pkg.installed`. A real apt repo is also published per release (see "Installing via apt" below), for anything that would rather add a source and run `apt-get install` than track sha256 pins by hand.

Two modules, each with its own workflow:

- **nginx-module-vts** - built for all three releases (jammy/noble/resolute).
- **nginx-module-lua** - built for **jammy only**. noble/24.04 and resolute/26.04 already have a working equivalent in Ubuntu's own archive - `libnginx-mod-http-lua` (which itself depends on `libnginx-mod-http-ndk`, `lua-resty-core`, and the distro's `libluajit-5.1-2` runtime, all real `.deb`s) - confirmed via `apt-cache policy` against all three releases. jammy has none of it, the same gap `nginx-dev`'s absence there causes for vts. A node on noble/resolute should just `apt-get install libnginx-mod-http-lua` directly; this repo's build only covers the jammy gap.

## Why this exists

Compiling a module on every node it's deployed to works, but repeats the same build on every server instead of once, and requires a full build toolchain (`build-essential`, dev libraries, and for jammy a pinned nginx source tarball) installed on production infrastructure just to produce one package. Building once here and installing a hash-pinned, signed `.deb` avoids both.

## How a module gets built

Each module has its own workflow, triggered manually (`workflow_dispatch`) with the upstream module's git tag(s) and a package revision to build.

**nginx-module-vts** is matrixed across the three OS releases the fleet actually runs, using the same build mechanism as the consuming Salt state does when it *does* still compile locally on a fresh clone:

- **jammy**: no `nginx-dev` package exists for it, so it builds against nginx.org's own upstream source (version-pinned + hash-verified) with `--with-compat`, relying on that flag's ABI-compatibility guarantee with the distro-patched binary.
- **noble/resolute**: uses the `nginx-dev` package, which ships the exact matching nginx source tree plus the real build's own configure flags (`conf_flags`) - so the module always matches whatever `nginx-core` is actually installed on that release, with no separate version to track.

**nginx-module-lua** only builds for jammy (see above for why), using the same nginx.org-source + `--with-compat` mechanism as vts's jammy leg. It bundles four upstream components into one package - `ngx_devel_kit` (a compile-time dependency of the Lua module, with no independent use in this fleet, so it isn't split into its own package the way Debian splits it), `openresty/lua-nginx-module` itself, and the two pure-Lua companion libraries current releases of it require, `lua-resty-core` and `lua-resty-lrucache`. Those two get installed to `/usr/share/lua/5.1/` - Debian/Ubuntu's own standard Lua 5.1 search path, already part of LuaJIT's compiled-in default `package.path` (confirmed: `luajit -e 'print(package.path)'` lists it on jammy already) - so no `lua_package_path` directive is needed anywhere, and the package needs nothing beyond the two `load_module` lines everything else here already uses. `lua-resty-core` hard-checks the exact `lua-nginx-module` version at nginx startup (an exact match, not a minimum) and refuses to load on a mismatch, so its git ref and `lua-nginx-module`'s git ref are a matched pair, not independently choosable - the workflow's own inputs document which versions were actually verified together.

Both modules' built `.so`(s) are packaged directly with `dpkg-deb --build` (confirmed installable via `dpkg -i`/`apt remove`, shows correctly in `dpkg -l`) rather than through nginx's own `nginx_mod` debhelper buildsystem - that expects the module source to ship its own `debian/` packaging, which neither `vozlt/nginx-module-vts` nor this repo's own bundle of upstream Lua components does. Modules go straight into `/etc/nginx/modules-enabled/` rather than the available+enabled symlink split real distro module packages use - that split exists so a module can be disabled without uninstalling it, which nothing here needs.

## Verifying a release

Every `.deb` has a matching `.cosign.bundle` - a keyless Sigstore signature bound to this repo's own GitHub Actions workflow identity (no private key involved). Verify with (use `build-nginx-vts.yml` or `build-nginx-lua.yml` in the regexp, matching whichever workflow actually built the file):

```
cosign verify-blob --bundle FILE.deb.cosign.bundle \
  --certificate-identity-regexp 'https://github.com/non7top/nginx-modules/.github/workflows/build-nginx-vts.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  FILE.deb
```

## Installing via apt

Every release also publishes a real, flat apt repo (`deb URL/ ./`, no
`dists/` hierarchy) - built and signed the same way
[non7top/apt-cosign](https://github.com/non7top/apt-cosign) publishes its own
demo repo, using that project's `apt-cosign-sign` instead of raw `cosign
sign-blob`.

**nginx-module-vts**, on the `apt-repo` branch. Because jammy/noble/resolute
builds of the same version aren't byte-identical (different nginx source,
different `Depends`), they can't share one flat Packages index - each
codename gets its own subdirectory, independently a complete repo:

```
deb [trusted=yes] sigstore+https://raw.githubusercontent.com/non7top/nginx-modules/refs/heads/apt-repo/<jammy|noble|resolute>/ ./
```

**nginx-module-lua**, on its own `apt-repo-lua` branch - deliberately
separate from `apt-repo`, since that branch is force-replaced whole on every
publish and vts's own workflow already owns it; publishing both modules to
the same branch would make whichever one runs last silently wipe out the
other's packages. Flat, no per-codename split needed - jammy is the only
target:

```
deb [trusted=yes] sigstore+https://raw.githubusercontent.com/non7top/nginx-modules/refs/heads/apt-repo-lua/ ./
```

(Nothing to install this way for noble/resolute - see above, use
`libnginx-mod-http-lua` from Ubuntu's own archive there instead.)

This needs [apt-cosign](https://github.com/non7top/apt-cosign) (0.4.0+)
installed first (`sigstore+https` isn't a scheme apt understands on its
own). Since these sources are GitHub-hosted, no policy is strictly required
- apt-cosign-method derives `non7top`/`nginx-modules` from the source URL
itself and trusts any workflow in that repo by default, which already
covers both modules (same owner/repo, both branches). To narrow that down
to just the workflow that actually produces each release (recommended -
it's the difference between "trust this whole repo" and "trust this one
build"), the two modules need separate, named `Sources::` blocks instead of
one flat `Enforce`, since each is built by a different workflow:

```
Acquire::sigstore::Sources::nginx-modules-vts {
    Match "https://raw.githubusercontent.com/non7top/nginx-modules/refs/heads/apt-repo/";
    Enforce::Repo::Pipeline "build-nginx-vts.yml";
};
Acquire::sigstore::Sources::nginx-modules-lua {
    Match "https://raw.githubusercontent.com/non7top/nginx-modules/refs/heads/apt-repo-lua/";
    Enforce::Repo::Pipeline "build-nginx-lua.yml";
};
```

(Consuming either of these alongside apt-cosign's own demo repo just adds a
third such block - see that project's README for the mechanism.)

`[trusted=yes]` tells apt to skip its own GPG check - there's no
`Release.gpg` or inline-signed `InRelease` here, the sigstore bundle
`apt-cosign-method` fetches alongside each file *is* the trust mechanism.
