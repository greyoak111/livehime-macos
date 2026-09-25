# LiveHime OBS fork source

LiveHime macOS v0.2 is OBS Studio with an in-tree LiveHime plugin. This
directory holds the complete source changes as a patch series against
upstream OBS Studio, so the released app can be rebuilt from public sources
(GPL-2.0-or-later).

- Upstream: https://github.com/obsproject/obs-studio
- Base: tag `32.2.2`, commit `ba2f32bdf791005443988a4955e963663e16b1ed`
- Patches: `patches/0001-…` to `patches/0051-…` (`git format-patch --binary`)

The plugin lives in `plugins/livehime` after applying: a Qt C++ dock and a
Swift core (`plugins/livehime/core`, SwiftPM, `swift test`). The series also
brands the bundle, adds the build script under `build-aux/livehime`, routes
OBS's Start/Stop Streaming through the LiveHime session, and lets mac-capture
keep or hide individual LiveHime windows (floating chat).

## Rebuild

Apple silicon Mac, Xcode, CMake 3.28+ (Intel apps are cross-built there too):

```sh
git clone https://github.com/obsproject/obs-studio.git obs-livehime
cd obs-livehime
git checkout -b livehime/main ba2f32bdf791005443988a4955e963663e16b1ed
git submodule update --init --recursive
git am /path/to/livehime-macos/obs-fork/patches/*.patch

# Development build (bundle id local.livehime.macos.dev):
./build-aux/livehime/build-macos.sh
# Release build (same identity as the published app):
BUNDLE_ID=local.livehime.macos ./build-aux/livehime/build-macos.sh
# Intel release build (into build_macos_x86_64):
ARCH=x86_64 BUNDLE_ID=local.livehime.macos ./build-aux/livehime/build-macos.sh
```

The app is written to `build_macos/frontend/RelWithDebInfo/LiveHime.app`;
releases ship it renamed to `LiveHimeMacApp.app`, packaged with
`build-aux/livehime/package-dmg.sh <LiveHime.app> <version> <out.dmg>`. The build script signs with
a local self-signed development identity it creates on first use; `SIGN=0`
skips signing.
