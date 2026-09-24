# OBS component used by LiveHime macOS v0.2.6

Since v0.2.0 the app itself is a modified OBS Studio build (not a nested
OBS.app as in v0.1.x).

- Repository: https://github.com/obsproject/obs-studio
- Base: tag `32.2.2`, commit `ba2f32bdf791005443988a4955e963663e16b1ed`
- Modifications: the patch series in [`obs-fork/patches`](../../obs-fork/patches),
  including the LiveHime plugin (`plugins/livehime`) and a mac-capture change
- License: GNU GPL v2 or any later version (see `COPYING`)
- Build: `BUNDLE_ID=local.livehime.macos build-aux/livehime/build-macos.sh`
  (Xcode generator, RelWithDebInfo, arm64, `ENABLE_BROWSER=OFF`,
  `OBS_VERSION_OVERRIDE=32.2.2`, `LIVEHIME_APP_VERSION=0.2.6`,
  `OBS_USER_CONFIG_SUBDIR=LiveHime`)
- Bundled files: [`DEPENDENCY-INVENTORY-v0.2.6.txt`](DEPENDENCY-INVENTORY-v0.2.6.txt)

Rebuild steps are in [`obs-fork/README.md`](../../obs-fork/README.md). The
repository does not contain generated app bundles, prebuilt dependency
archives, the Windows Bilibili client, or signing keys.
