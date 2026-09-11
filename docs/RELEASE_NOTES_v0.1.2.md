# LiveHime macOS v0.1.2

LiveHime macOS v0.1.2 is an unofficial third-party macOS adaptation of the Bilibili LiveHime workflow. It is provided for learning, research and community exchange, with no commercial purpose or affiliation with Bilibili, OBS Project, or the original Windows LiveHime authors.

## This release

- Adds a native “检查更新” menu item and authenticated-panel button that open the canonical GitHub Releases page.
- Keeps the update boundary explicit: the app does not download, replace, terminate OBS, or restart itself in the background.
- Documents a seamless replacement path for users of v0.1.0 and v0.1.1. The production Bundle ID and Keychain service remain stable, so Finder replacement preserves the login session, WebKit data and user OBS configuration.
- Adds a guarded installer script that checks the production Bundle ID and code signature, refuses to replace running LiveHime/OBS, stages the candidate, and restores the previous app if replacement fails.
- Retains the stable OBS output gating, stop/logout safety and proxy-route diagnostics from v0.1.1.

## Upgrade

Download the arm64 zip from [GitHub Releases](https://github.com/greyoak111/livehime-macos/releases), stop LiveHime and its bundled OBS, rename the versioned app to `LiveHimeMacApp.app`, and choose Replace in `/Applications`. Do not delete Keychain, WebKit, or Application Support data. Full instructions are in [`docs/UPGRADING.md`](UPGRADING.md).

## Validation

- Apple Silicon arm64 macOS build.
- Swift tests: 50 passed, 1 environment-gated Keychain integration test skipped.
- Python compatibility and bundle-safety tests: 21 passed.
- Bundle signature, nested OBS signature, WebSocket plugin and arm64 checks passed.
- No account data, cookies, stream keys, Windows binaries, extracted Bilibili resources or signing keys are included.
