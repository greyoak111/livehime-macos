# LiveHimeAdapter

A native macOS-side host derived from the current LiveHime 8.6 static analysis.

It deliberately contains no login HTTP client, password crypto, or CAPTCHA handling. The official mini-login page remains responsible for password, QR, SMS, CAPTCHA/Geetest, and secondary verification. `LiveHimeMacApp` is a small AppKit + WKWebView host that injects the Windows-compatible `biliBridgePc` auth calls (`auth/setRefreshToken` and `auth/setCookies`) plus the `livehime_login` shim, then validates the resulting cookie jar through the read-only nav endpoint.
After authentication the native panel reads the current room and available live
areas. “开始直播” performs the explicit Bilibili start-live/upstream request,
pushes the returned RTMP server/key into OBS through WebSocket v5, then starts
OBS. “结束直播（关闭直播间）” independently asks Bilibili to close the room
and asks OBS to stop output, even when OBS is unresponsive or this app was
reopened during a broadcast. The room status is queried again before the UI
reports confirmed offline. A WebSocket acknowledgement alone is not a stop
confirmation; the adapter waits until neither active nor reconnecting.

Run:

```sh
swift test
```

Build the macOS host target with `swift build`. The authenticated panel now
contains the room lookup, area selection, bundled OBS launcher, and the first
end-to-end start/stop path.

Create a local signed development app bundle with:

```sh
scripts/package-app.sh
open dist/LiveHimeMacApp.app
```

When the sibling OBS checkout is present, the script stages the complete
upstream `OBS.app` (including Qt frameworks, plugins and `obs-websocket`) at
`Contents/Resources/OBS.app`. This makes the development artifact
self-contained; the host connects to OBS over localhost and can launch the
nested app from the native panel. To build only
the login host, use `LIVEHIME_INCLUDE_OBS=0 scripts/package-app.sh`. A custom
OBS build can be selected with `OBS_APP_SOURCE=/path/to/OBS.app`.

The delivered artifact is one user-facing **LiveHimeMacApp.app**. OBS remains
inside `Contents/Resources/OBS.app` as a private capture/encoding backend; it is
launched and controlled by the native host and marked as a UI element so it does
not create a second Dock or menu-bar application. The bundle uses a persistent
**local development certificate**. The certificate
and non-extractable private key are stored in a dedicated user keychain under
`~/Library/Application Support/LiveHime/DevelopmentSigning`, outside the source
tree and app bundle. Packaging temporarily includes that keychain for private-key
lookup and restores the original user keychain search list afterwards. It does
not install a trusted root or modify TCC. Keep this identity across builds: a new
certificate is a new privacy identity. This is a local development build, not a
notarized or distributable release.

Both the host and bundled OBS contain camera, microphone, screen and system-audio
usage descriptions. The macOS permission panel in LiveHime checks the responsible
host's current authorization and only requests permission when its button is
clicked. If the saved OBS scenes contain screen capture and screen access is not
granted, the host delays launching OBS to prevent immediate repeat prompts.
The restart action checks streaming/reconnecting and recording state, quits only
the exact bundled OBS path, and then reopens the same LiveHime bundle. It refuses
to restart when output status is active or unknown.

The main panel's “退出登录（自动关播）” action is the account-switch path. If
the room is live, it first stops OBS and sends Bilibili's room-close request in
parallel, waits for both OBS output and the server room state to be confirmed
offline, and only then removes the local Keychain session and Bilibili WebView
data. A failed or ambiguous close leaves the account signed in so the user can
retry without losing the credentials needed to close the room.

For a permission-only window that does not restore login or launch OBS:

```sh
open dist/LiveHimeMacApp.app --args --permissions-only
```

After granting access to **LiveHime macOS**, use “重启应用以应用授权”. Screen,
microphone and camera are separate permissions. “检查采集权限” checks display
enumeration only; it does not capture frames, record audio, or go live. Sanitized
permission results go to `~/Library/Logs/LiveHime/capture-permissions.json`.
The first switch from an old ad-hoc build may require permission approval again.

Quit LiveHime before packaging. For host-only changes, preserve the bundled OBS
runtime with `LIVEHIME_UPDATE_HOST_ONLY=1 scripts/package-app.sh`. Full packaging
also requires the bundled OBS to be closed. `scripts/verify-bundle.sh` verifies
signatures, privacy strings and stable certificate-based identities.

`LoginSession.swift` adds a Keychain-backed `LoginSessionStore` and an explicit `LoginSessionCoordinator` state machine (`signedOut`, `signedIn`, `secondaryValidationPending`). A normal result stores the opaque refresh token; the Windows-style cookie result stores only the authenticated `SESSDATA` cookie value after `/x/web-interface/nav` succeeds. The app never logs either value. The authenticated panel probes OBS WebSocket v5 on `127.0.0.1:4455`, displays room/area status, and exposes the integrated start/stop flow when OBS is configured with its WebSocket server.
