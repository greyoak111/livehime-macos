# OBS component used by LiveHime macOS v0.3.0

Since v0.2.0 the app itself is a modified OBS Studio build (not a nested
OBS.app as in v0.1.x).

- Repository: https://github.com/obsproject/obs-studio
- Base: tag `32.2.2`, commit `ba2f32bdf791005443988a4955e963663e16b1ed`
- Modifications: the patch series in [`obs-fork/patches`](../../obs-fork/patches),
  including the LiveHime plugin (`plugins/livehime`) and a mac-capture change
- License: GNU GPL v2 or any later version (see `COPYING`)
- Build: `BUNDLE_ID=local.livehime.macos build-aux/livehime/build-macos.sh`
  (Xcode generator, RelWithDebInfo, arm64, `ENABLE_BROWSER=OFF`,
  `OBS_VERSION_OVERRIDE=32.2.2`, `LIVEHIME_APP_VERSION=0.3.0`,
  `OBS_USER_CONFIG_SUBDIR=LiveHime`); the Intel app adds `ARCH=x86_64`
  (cross-built on Apple silicon from the universal obs-deps)
- Bundled files: [`DEPENDENCY-INVENTORY-v0.3.0.txt`](DEPENDENCY-INVENTORY-v0.3.0.txt) (arm64),
  [`DEPENDENCY-INVENTORY-v0.3.0-x86_64.txt`](DEPENDENCY-INVENTORY-v0.3.0-x86_64.txt) (Intel)
- Both apps were built from the series through patch 0063 (0060 and 0061
  change only tests).
- Browser add-on 1.0.0: `obs-browser` from the same tree with
  [`obs-fork/browser-addon`](../../obs-fork/browser-addon) applied, built with
  `BROWSER_ADDON=1` and packaged by `build-aux/livehime/package-browser-addon.sh`;
  it contains the Chromium Embedded Framework (see [`../CEF`](../CEF)).

Rebuild steps are in [`obs-fork/README.md`](../../obs-fork/README.md). The
repository does not contain generated app bundles, prebuilt dependency
archives, the Windows Bilibili client, or signing keys.
