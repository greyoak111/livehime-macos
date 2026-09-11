# LiveHime macOS v0.1.1

LiveHime macOS v0.1.1 is an unofficial third-party macOS adaptation of the
Bilibili LiveHime workflow. It is provided for learning, research and community
exchange, with no commercial purpose or affiliation with Bilibili, OBS Project,
or the original Windows LiveHime authors.

## This release

- Keeps login, QR code, SMS, image verification, secondary verification and
  platform-provided face verification inside the native macOS host.
- Persists the authenticated session in Keychain and clears WebKit login data
  during sign-out, so switching accounts does not restore the previous account.
- Controls the bundled OBS backend through OBS WebSocket v5 and passes the
  latest Bilibili RTMP server and stream key in memory.
- Requires stable OBS output before reporting a successful start. A reconnecting
  OBS output is shown as a rejected or unconfirmed stream instead of a false
  success.
- Stops OBS output and the Bilibili room independently during shutdown, and
  protects logout while either side remains unconfirmed.
- Includes the OBS GPL notice and build provenance under
  `ThirdPartyLicenses/OBS/`.

## Validation

- Apple Silicon arm64 macOS build.
- Swift tests: 48 passed, 1 environment-gated Keychain integration test skipped.
- Python compatibility and bundle-safety tests: 21 passed.
- Bundle signature, nested OBS signature, WebSocket plugin and arm64 checks passed.
- Manual login, account switching, face verification page, start, stop and
  account logout flows were exercised with a real test account.
- Bilibili streaming requires a network exit accepted by the platform's ingest
  CDN. Proxy rules that send the RTMP connection through an overseas exit can
  produce an immediate disconnect and OBS reconnect loop.

## Distribution boundary

The public source tree does not contain account data, cookies, stream keys,
Windows binaries, extracted Bilibili resources, signing keys or a generated
`.app`. Any redistributed OBS-containing bundle must be accompanied by the
corresponding OBS source or a valid GPLv2 written offer, plus the applicable
third-party notices and dependency inventory.
