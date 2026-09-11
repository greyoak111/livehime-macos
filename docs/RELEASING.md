# v0.1.1 release checklist

1. Run `swift test` under `macos-livehime-adapter/`.
2. Build and package on Apple Silicon macOS, then run `scripts/verify-bundle.sh`.
3. Generate the actual bundle dependency inventory and copy all applicable notices into the
   distributable app. For the current candidate, run:

   ```sh
   python3 scripts/generate-bundle-inventory.py \
     macos-livehime-adapter/dist/LiveHimeMacApp-v0.1.1.app \
     ThirdPartyLicenses/OBS/DEPENDENCY-INVENTORY-v0.1.1.txt
   ```

   The source-only repository does not include the generated app; the inventory must match the
   exact binary attached to a release.
4. Verify that no account data, cookies, tokens, stream keys, screenshots, logs, Windows
   binaries, extracted Bilibili resources, or signing keys are staged.
5. Keep `ThirdPartyLicenses/OBS/BUILD-INFO.md` synchronized with the exact OBS commit and
   build parameters. For a redistributed OBS binary, provide the corresponding source or a
   valid GPLv2 written offer.
6. Create the annotated Git tag `v0.1.1` and publish release notes describing this as an
   unofficial third-party macOS adaptation for learning/research/community exchange.
