# v0.1.2 release checklist

1. Run `swift test` under `macos-livehime-adapter/`.
2. Build and package on Apple Silicon macOS, then run `scripts/verify-bundle.sh`.
3. Generate the actual bundle dependency inventory and copy all applicable notices into the
   distributable app. For the current candidate, run:

   ```sh
   python3 scripts/generate-bundle-inventory.py \
     macos-livehime-adapter/dist/LiveHimeMacApp-v0.1.2.app \
     ThirdPartyLicenses/OBS/DEPENDENCY-INVENTORY-v0.1.2.txt
   ```

   The source-only repository does not include the generated app; the inventory must match the
   exact binary attached to a release.
4. Verify that no account data, cookies, tokens, stream keys, screenshots, logs, Windows
   binaries, extracted Bilibili resources, or signing keys are staged.
5. Keep `ThirdPartyLicenses/OBS/BUILD-INFO.md` synchronized with the exact OBS commit and
   build parameters. For a redistributed OBS binary, provide the corresponding source or a
   valid GPLv2 written offer.
6. Create the annotated Git tag `v0.1.2` and publish release notes describing this as an
   unofficial third-party macOS adaptation for learning/research/community exchange.

## Upgrade and update UX

The formal application identity must remain stable across releases:

- Keep `CFBundleIdentifier` as `local.livehime.macos` for the production app. Validation and
  compatibility builds must continue to use a different identifier.
- Keep the Keychain service mapping and WebKit data store tied to that production identity. A
  version bump must not silently change the service/account names or clear those stores.
- Ship the `.app` inside a zip. The documented upgrade path is to quit LiveHime and the bundled
  OBS, then drag the new app into `/Applications` and choose “Replace”. This preserves the
  Keychain session, Bilibili WebKit data, and user data outside the app bundle while allowing the
  old app to be retained temporarily for rollback.

The main panel's “检查更新” action should open the canonical GitHub Releases page:
`https://github.com/greyoak111/livehime-macos/releases`. It is a release-page navigator, not an
automatic updater: it must not download an unverified asset, overwrite `/Applications`, terminate
OBS, or restart the app. Release notes and the README must describe the same manual replacement
steps in [`docs/UPGRADING.md`](UPGRADING.md). Before publishing, verify that the button is
reachable after login and while signed out, that it opens the system/browser release page, and
that it does not affect the current login, stream, or OBS state.

The upgrade instructions must explicitly state that users should stop LiveHime and the bundled OBS
before replacement, use the same production Bundle ID, and avoid deleting Keychain, WebKit, or
Application Support data. If a release changes any of those identities or storage locations, treat
it as a migration requiring a separate design and validation pass; do not silently publish it as a
seamless update.
