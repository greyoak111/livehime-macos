# OBS component used by LiveHime macOS v0.2.8

Since v0.2.0 the app itself is a modified OBS Studio build (not a nested
OBS.app as in v0.1.x).

- Repository: https://github.com/obsproject/obs-studio
- Base: tag `32.2.2`, commit `ba2f32bdf791005443988a4955e963663e16b1ed`
- Modifications: the patch series in [`obs-fork/patches`](../../obs-fork/patches),
  including the LiveHime plugin (`plugins/livehime`) and a mac-capture change
- License: GNU GPL v2 or any later version (see `COPYING`)
- Build: `BUNDLE_ID=local.livehime.macos build-aux/livehime/build-macos.sh`
  (Xcode generator, RelWithDebInfo, arm64, `ENABLE_BROWSER=OFF`,
  `OBS_VERSION_OVERRIDE=32.2.2`, `LIVEHIME_APP_VERSION=0.2.8`,
  `OBS_USER_CONFIG_SUBDIR=LiveHime`); the Intel app adds `ARCH=x86_64`
  (cross-built on Apple silicon from the universal obs-deps)
- Bundled files: [`DEPENDENCY-INVENTORY-v0.2.8.txt`](DEPENDENCY-INVENTORY-v0.2.8.txt) (arm64),
  [`DEPENDENCY-INVENTORY-v0.2.8-x86_64.txt`](DEPENDENCY-INVENTORY-v0.2.8-x86_64.txt) (Intel)
- The v0.2.8 Intel app was built from the series through patch 0049 (which
  only adds the `ARCH` build option and makes the updater pick the archive for
  its architecture); the Apple silicon app from the series through 0048.

Rebuild steps are in [`obs-fork/README.md`](../../obs-fork/README.md). The
repository does not contain generated app bundles, prebuilt dependency
archives, the Windows Bilibili client, or signing keys.
