# Maintaining the iOS Factory

Traps this Factory has actually hit, plus the honest list of what has and
has not been verified. Read `UPSTREAM.md` first for the Bump procedure.

## UNVERIFIED - needs the Mac runner

This Factory was authored and Linux-validated on 2026-08-25 with **no
macOS machine available**. Nothing below has ever been executed; the
first session on the `macos` runner (runbooks/mac-runner.md) must verify
each item before anything is published:

1. **xcodebuild at all**: the Pin has never been compiled by us - neither
   `xcodebuild build` for the simulator nor `gym` archives. SwiftPM
   resolution, Xcode 26.2 behaviour, APP_BUILD_FLAGS propagation
   (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` / `INFOPLIST_PREPROCESSOR_DEFINITIONS`)
   are all unproven.
2. **The branding lane behaviour**: `aity_apply_identity` is a
   transcription of upstream's `build_ipa_in_house` - reviewed against
   their source, never run. In particular: `update_app_identifier` /
   `update_app_group_identifiers` / `update_keychain_access_groups` /
   `set_info_plist_value ... subkey:` against the Pin's real project, the
   Action Extension `InfoPlist.xcstrings` JSON rewrite, and the
   fastlane-plugin-appicon regeneration of `AppIcon.appiconset` from our
   1024px `branding-icon.png`.
3. **URL-scheme rewriting at runtime**: the sed itself is proven on Linux
   (the octype markers match, output parses, schemes land in
   `CFBundleURLTypes`), but the OIDC round trip
   `aitydrive://ios.aity.tech` / `aitydrive-staging://ios.aity.works`
   against Keycloak has never been driven (also gated on stream S3
   creating the `drive-ios` clients).
4. **The XCUITest smoke**: `smoke/project.yml` + xcodegen have never
   generated the project; a ui-testing bundle with no host application
   (launching by `XCUIApplication(bundleIdentifier:)`) is a documented
   pattern but unproven here; the `Welcome to <app name>` / `Start setup`
   accessibility queries against the real setup screen are untested; the
   `com.apple.CoreSimulator.SimDeviceType.iPhone-16` device type must
   exist in the runner's simulator runtime (override with
   `AITY_SMOKE_DEVICE_TYPE`).
5. **Everything signing/store**: `setup_ci` keychain flow, `match` against
   `drive/certificates` (repo exists, store NOT bootstrapped - needs the
   Apple org account, publisher-accounts.md), `pilot`/`deliver` with the
   ASC API key, export options including our fileprovider-ui addition
   (upstream's export map omits it - ours includes it deliberately).
6. **Gemfile.lock on the Mac**: resolved on Linux ruby 3.2 with darwin
   platforms added (`x86_64-darwin-22`, `arm64-darwin-23`); `bundle
   install` under the runner's brew ruby may want `bundle lock
   --add-platform` for its exact platform string.
7. **Unsigned-build entitlements**: the smoke build rewrites keychain
   access groups with the placeholder team `AITYSIMULATE`
   (CODE_SIGNING_ALLOWED=NO ignores entitlements; app groups work
   unprovisioned on the simulator) - assumption, not fact.
8. **Branding runtime rendering**: theme colors (`#b80818` light /
   `#780611` dark brand), the white login background + red mark, the
   sidebar "Source code (GPLv3)" link, the hidden Documentation row
   (empty `branding.url-documentation`), and the locked profile skipping
   the URL step all follow from reading the Pin's source; screenshots on
   Mac day decide whether `cssRecords` tuning is needed.

When an item is verified, move it from this list into the log below with
the date and what was found.

## Traps already hit (Linux authoring, 2026-08-25)

- **`git cat-file -e HEAD:.` fails for the repo root** - the materialize
  `--check` rule special-cases new root-level files (`Gemfile.lock`).
- **`branding-assets/` is tracked-but-empty at the Pin** and the xcodeproj
  copy phase counts `branding-*.png` files to decide between it and the
  default `com.owncloud.ios-app/` assets: ship ALL asset files, never a
  partial set, or the build silently mixes ownCloud defaults with ours.
- **`branding-icon.png` is removed from the bundle by the copy phase** -
  it is only the appicon-generator input, do not reference it at runtime.
- **`branding.profile-definitions` (array form) has no consumer at
  v12.7.0** - the live bookmark-setup path reads the flat
  `branding.profile-url` / `branding.profile-allow-url-configuration` /
  `branding.profile-bookmark-name` keys (BookmarkComposerConfiguration),
  which is what our plists set. The single locked profile IS those keys.
- **ownBrander's `Colors.NavigationBar.*` theme keys are dead at this
  Pin** - `generateThemeStyle()` consumes only `ThemeStyle`, `Identifier`,
  `Name`, `darkBrandColor`, `lightBrandColor`, `Styles`, `cssRecords`.
- **Keycloak advertises `registration_endpoint`**, and upstream defaults
  `authentication-oauth2.oidc-register-client` to true - our plists turn
  it off so setup does not attempt (and fail) dynamic client registration.
- **`CFBundleURLName` entries stay `com.owncloud.*`** on purpose: they are
  internal URL-type identifiers the app looks up
  (`Branding.appURLSchemesForBundleURLName`); upstream's own branding flow
  renames only the scheme strings.
- **The two Branding.plists are full copies** (a copy-based overlay cannot
  merge plists): `scripts/check-plists.py` enforces identical key sets and
  pins the env-specific values to the identity table - run it before
  pushing plist changes; the lint job runs it anyway.
- **The brand master has a stray speck** (a faint red trace artifact left
  of the cloud) baked into `meta/brand/logo.svg`'s embedded PNG; it is in
  every derived asset. Fixing it is a meta/brand change, not an ios one.
- **Local dev tooling**: `scripts/generate-assets.py` needs
  `pip install cairosvg pillow` (a venv is fine) and a bold DejaVu or
  Liberation TTF for the STG badge.

## Standing duties

- **Every Bump: re-diff the Fastfile transcription** against upstream's
  `build_ipa_in_house` (see UPSTREAM.md step 3). This is the price of the
  parameterised shared-framework id and the simulator lane; pay it.
- Keep `scripts/check-plists.py` in lockstep with any Branding.plist
  change (it is the identity-table contract, not decoration).
- The `lint` job must stay green on every push to main - it is the only
  continuously-running validation this Factory has until the Mac exists.

## The Action Extension keeps upstream's bundle id (hit 2026-08-27)

First real run on the `macos` runner failed with `Embedded binary's bundle
identifier is not prefixed with the parent app's bundle identifier`
(embedded `com.owncloud.ios-app.ownCloud-Action-Extension`, parent
`tech.aity.drive.staging`). Cause: every target takes its id from
`PRODUCT_BUNDLE_IDENTIFIER`, and `update_app_identifier` reads
`CFBundleIdentifier` from the plist to decide what to do - but
`ownCloud Action Extension/Info.plist` does not define that key at this Pin
(its only CFBundle* keys are Icons, PrimaryIcon, SymbolName, DisplayName),
so the action silently skipped it. The lane now sets
`PRODUCT_BUNDLE_IDENTIFIER` per target with Xcodeproj after upstream's
calls, and fails if a mapped target name is missing - check that map on
every Bump.

Related: two log traps found in the same run. `xcodebuild | tee` blew
GitLab's 4 MB job-log cap and truncated the job before the error was
visible (log to a file, print errors on failure, ship the log as an
artifact), and `ensure_xcode_version` needs the abandoned `xcode-install`
gem, which is not in the Pin's Gemfile.

