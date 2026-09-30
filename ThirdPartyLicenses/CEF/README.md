# Chromium Embedded Framework (optional browser add-on)

The optional browser source add-on (`LiveHime-BrowserAddon-v<version>-<arch>.zip`,
installed from the app's Updates tab) contains the Chromium Embedded Framework.
The app itself does not.

- Version: CEF 6533 revision 5 (Chromium 127.0.6533.120), the build OBS Studio
  32.2.2 pins in `CMakePresets.json`
- Source of the binaries: `cef_binary_6533_macos_<arch>_v5.tar.xz` from
  `https://cdn-fastly.obsproject.com/downloads/`, checked against the SHA-256
  in `CMakePresets.json`
- License: BSD, see [`LICENSE.txt`](LICENSE.txt); the add-on carries it as
  `Contents/Resources/LICENSE-CEF.txt`
- Chromium's own third-party notices are built into CEF and shown at
  `chrome://credits`
- The add-on's plugin, obs-browser, is part of OBS Studio (GPL v2 or later);
  its LiveHime changes are in [`obs-fork/browser-addon`](../../obs-fork/browser-addon)
