# Capture permissions repair — 2026-09-10

User report: screen capture inside nested OBS repeatedly requests permission for
LiveHimeMacApp despite previously enabling OBS permissions.

Verified cause in the shipped development package: the outer host had only a
CDHash designated requirement, which changes when its executable is rebuilt.
The host also lacked capture privacy usage strings. The screenshot attributes
capture responsibility to LiveHimeMacApp. The old launcher selected any running
OBS with the same bundle identifier, including standalone installations.

Implemented:
- Persistent local certificate signing in an isolated user keychain, with default
  certificate-pinned designated requirements for each real bundle identifier.
- Host and OBS camera, microphone, screen and system-audio privacy descriptions.
- Permission status, explicit requests, display enumeration check and safe restart.
- Screen permission gate before launching saved OBS screen-capture scenes.
- Exact nested OBS path matching; separate OBS instances are no longer silently reused.
- Restart refuses active/reconnecting/recording outputs or unknown output status.
- StopStream acknowledgement requires polling to a confirmed inactive status; bounded
  timeouts and per-operation sockets prevent shared-response hangs.

Verification:
- swift test: 25 tests passed, including nine OBS transport tests using a real
  localhost-only WebSocket fixture (no actual livestream is started).
- Release app bundled; deep strict signature verification passed.
- Host and nested OBS privacy descriptions and certificate requirements verified.
- Two different host executables signed with the same persistent certificate:
  identical DR; new host satisfies the old host requirement. Evidence lives in
  .build/signing-check/result.json.
- User keychain search list restored to login.keychain-db; no system trust or TCC
  database modifications were made.
- New permission-only window opened and its controls verified through accessibility.

Pending user/runtime verification:
The final signed host initially reported screen_authorized=false, microphone=0,
camera=0 (not yet requested). The user must grant the final host identity access
and restart it. Display enumeration and actual OBS capture preview have NOT yet
been verified after that authorization. No new livestream was started by these tests.

Keep ~/Library/Application Support/LiveHime/DevelopmentSigning for later builds.
Replacing that certificate creates a new privacy identity. This is a local
self-signed development package, not a notarized distribution build.
