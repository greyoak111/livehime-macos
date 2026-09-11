# OBS component used by LiveHime macOS v0.1.2

The local development bundle uses an OBS Studio checkout as an internal,
separately launched backend. The exact checkout used during v0.1.2 development
was:

- Repository: https://github.com/obsproject/obs-studio
- Commit: `6b3e550729f125b6c5b3767df88c08f5aef9d264`
- Bundle metadata override used by the local build: `OBS_VERSION_OVERRIDE=32.2.2` (this is not a claim that the checkout is the official 32.2.2 release tag)
- License: GNU GPL v2 or any later version
- Integration: nested `OBS.app`, controlled over OBS WebSocket v5 on localhost

The public repository intentionally does not contain the generated OBS.app,
prebuilt dependency archives, or the Windows Bilibili client. To reproduce the
local backend, obtain the exact OBS source commit above and build it with the
project's macOS packaging script. Any redistributed binary must be accompanied
by the corresponding source and the applicable third-party notices.
