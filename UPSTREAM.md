# Upstream: owncloud/ios-app

## The Pin

| | |
|---|---|
| Repository | https://github.com/owncloud/ios-app |
| Pin | `v12.7.0` (commit `3fac7eade3e22f75ea4359718ee5eaef5ca6c018`) |
| Licence | GPLv3 (App Store stance: meta ADR 0003) |
| SDK | https://github.com/owncloud/ios-sdk as the `ios-sdk` git submodule, checked out at the commit the Pin records (`275bad5ac6c03012882e01c50d3862f93105a15a` at v12.7.0) - it has no Pin of its own |
| Xcode | per the Pin's `.xcode-version` (26.2 at v12.7.0; requires macOS 26 on the runner) |

The Pin lives in `.gitlab-ci.yml` as `UPSTREAM_TAG` (Renovate-annotated,
watched from `meta`). `scripts/materialize.sh <production|staging>` clones
it into `build/upstream/` (gitignored, never committed - ADR 0001), lays
`overlay/common/` then `overlay/<env>/` over it, copies the build recipe
(`fastlane/`, `Gemfile`, `Gemfile.lock`) and applies `patches/` (none).

## Upstream mechanisms this Factory relies on

Everything below is upstream's OWN branding surface - we configure it, we
do not invent parallel mechanisms:

- `ownCloud/Resources/Theming/Branding.plist` - the branded configuration
  (empty dict at the Pin; our Overlay replaces it). Runtime keys are
  documented in `doc/configuration.adoc`; keys with `$[x]` use the SDK's
  flat syntax (`ios-sdk/.../NSDictionary+OCExpand.m`). Setting
  `branding.organization-name` is what flips `Branding.isBranded`.
- `ownCloud/Resources/Theming/branding-assets/` - login/splash imagery and
  the app-icon source; a build phase in `ownCloud.xcodeproj` (driven by
  `branding-assets-input/output.xcfilelist`) copies `branding-*.png` into
  the bundle when the folder is non-empty, else falls back to the default
  `com.owncloud.ios-app/` set.
- `fastlane/Fastfile` lane `build_ipa_in_house` - upstream's branding
  build: reads `build.flags`, `build.custom-app-scheme`,
  `build.custom-auth-scheme`, `build.app-group-identifier` from
  Branding.plist; seds the `octype="app"` / `octype="auth"` URL-scheme
  markers in `ownCloud/Resources/Info.plist`; rewrites bundle ids via
  `update_app_identifier` on seven Info.plists; rewrites app groups and
  keychain access groups in six entitlements files; sets
  `OCAppGroupIdentifier` / `OCKeychainAccessGroupIdentifier` /
  `NSExtensionFileProviderDocumentGroup`; regenerates
  `AppIcon.appiconset` from `branding-assets/branding-icon.png`
  (fastlane-plugin-appicon); passes `APP_BUILD_FLAGS` to xcodebuild.
  Our `fastlane/Fastfile` (`aity_apply_identity` and friends) is a faithful
  transcription of these steps - see the header comment there for why we
  do not call their lane directly.
- `doc/BUILD_CUSTOMIZATION.md` - the `build.flags` values
  (`DISABLE_APPSTORE_LICENSING`, `DISABLE_PLAIN_HTTP`, ...).

## How to Bump

1. Renovate (from `meta`) proposes the new `UPSTREAM_TAG`.
2. `scripts/materialize.sh production --check && scripts/materialize.sh
   staging --check` - path drift and patch application (the `lint` CI job
   runs exactly this).
3. Diff upstream's `fastlane/Fastfile` `build_ipa_in_house` between the
   old and new Pin, and fold any change into our `aity_apply_identity` /
   `aity_apply_signing` / `aity_generate_appicon` transcription. This is
   the one standing manual duty of this Factory.
4. Re-check the Branding keys used in `overlay/*/.../Branding.plist`
   against the new Pin's `doc/configuration.adoc`.
5. If `.xcode-version` changed: `xcodes install <version>` on the Mac
   runner first (runbooks/mac-runner.md).
6. Refresh `Gemfile.lock` if the Pin's `fastlane/Pluginfile` changed
   (`bundle lock` inside a materialised tree, copy back to the repo root).
7. Run the simulator smoke, then tag `v<upstream>-aity-1`.

## Trademark

"ownCloud" never appears in our group, repo, package, bundle or product
names. The upstream tree keeps its internal names (`ownCloud.xcodeproj`,
`ownCloudApp.framework`, source headers, GPL notices) - those are
upstream's code and licence text, not our product identity, and the GPL
notices are never removed (meta ADR 0003).
