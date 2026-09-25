# Third-party licenses

This directory records the licenses and build provenance for components used by
LiveHime macOS. The host source is released under the root `LICENSE`.

OBS Studio is a separate GPL-2.0-or-later component. Its license and authorship
notices are copied here, and the exact source commit is recorded in
`OBS/BUILD-INFO.md`. OBS plugins and dependencies retain their own licenses;
when a distributable app bundle is produced, its complete dependency inventory
must be generated from the actual bundle before release.

The architecture diagram in `docs/diagrams/` was generated with
[Archify](https://github.com/tt-a1i/archify) (MIT, commit `9e35d2b`); its
license is in `Archify/LICENSE`. The generated HTML also embeds the fonts'
own license notices. Archify is a documentation tool only and is not part of
the app.
