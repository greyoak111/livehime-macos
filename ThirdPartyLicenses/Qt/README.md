# Qt

LiveHime bundles Qt 6.11.1 from the OBS prebuilt dependencies
(`obs-deps-qt6`, release 2026-07-15), as OBS Studio does. Qt is available
under LGPL-3.0-only or GPL-2.0/GPL-3.0; the license texts are in this folder
(`LGPL-3.0-only.txt`, which builds on `GPL-3.0-only.txt`). Individual files
keep their own notices (the patched file below is BSD-3-Clause).

## Modified component (since v0.3.1)

One file in the app is a modified Qt build:
`Contents/PlugIns/platforms/libqcocoa.dylib`, the Qt macOS platform plugin.

- Source: `qtbase-everywhere-src-6.11.1.tar.xz` from
  https://download.qt.io/archive/qt/6.11/6.11.1/submodules/
  (SHA-256 `d9594a31228aa23ad6b531719a29b45f0f3989fe6c136d45767ea179f233c1ac`)
- Change: `build-aux/livehime/qt/qcocoa-tray-icon-current-event.patch` in the
  OBS fork (patch 0064 in [`obs-fork/patches`](../../obs-fork/patches)), a
  backport of Qt commit `6192d9edd00caa14ed6b67c32c0cd8cfe95cf815` ("macOS:
  Don't assume the current event is a mouse event in the tray icon"), which
  stops the app from aborting when its menu bar icon is clicked on macOS 27.
- Build: `build-aux/livehime/qt/patch-qcocoa.sh`, run by `build-macos.sh`,
  with the obs-deps qtbase settings for arm64 and x86_64.

The other Qt libraries and plugins are the unmodified obs-deps binaries. The
Qt libraries are separate dynamic frameworks inside the app bundle and can be
replaced with compatible builds.
