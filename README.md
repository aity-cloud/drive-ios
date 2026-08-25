# Aity Drive for iOS - Factory

Produces the Aity Drive iOS app for both Environments (production
`drive.aity.tech`, staging `drive.aity.works`) from upstream
[owncloud/ios-app](https://github.com/owncloud/ios-app) at a pinned tag,
as an overlay factory: this repository holds only the Pin, the Branding,
the Patches (none) and the CI recipe - never a copy of the upstream tree.

- `UPSTREAM.md` - the Pin, the upstream mechanisms used, how to Bump
- `PATCHES.md` - patch inventory (empty, by design)
- `MAINTAINING.md` - traps, standing duties, and the UNVERIFIED list
  (no macOS runner existed when this Factory was authored)
- `overlay/` - Branding.plist and branding assets per Environment
- `fastlane/` - build/smoke/publish lanes (copied into the materialised
  tree; transcription of upstream's own branding flow)
- `smoke/` - standalone XCUITest login-screen smoke (xcodegen project)
- `scripts/materialize.sh` - clone Pin + submodule, lay overlay, apply
  patches; `--check` validates overlay paths against the upstream tree

Work on it:

```sh
# produce a buildable tree (any OS; building it needs a Mac)
scripts/materialize.sh staging

# on a Mac, from the materialised tree
cd build/upstream
bundle install
bundle exec fastlane ios build_simulator_smoke
```

Releases are built and published by GitLab CI only (tags
`v<upstream>-aity-<n>`); the manual `promote` job is the only path to the
App Store. Source is mirrored to
[github.com/aity-cloud/drive-ios](https://github.com/aity-cloud/drive-ios)
(a consumer, never pushed to by hand).

The app is GPLv3, upstream's copyright; see `UPSTREAM.md` and meta ADR
0003 for the licence stance.
