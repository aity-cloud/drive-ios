# Maintaining the iOS Factory

Traps this Factory has actually hit, plus the honest list of what has and
has not been verified. Read `UPSTREAM.md` first for the Bump procedure.

## UNVERIFIED - needs the Mac runner

**Partly verified 2026-08-27** - first green run on the `macos` runner
(MacBook Air, Xcode 26.2, job 16140937726): materialize + the full
`aity_apply_identity` transcription (schemes rewritten, ids set on all 7
targets, app group, appicon), the unsigned simulator build, `simctl`
install of `tech.aity.drive.staging` ("Aity Drive (staging)"), xcodegen of
the smoke project and the XCUITest run all execute for real. Everything
signing-related (match, gym, pilot, deliver, notarisation) remains
unverified - no Apple team, no certificates.


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

## Tier 2: how the OIDC login is driven (2026-08-27)

`smoke/AityDriveSmokeUITests/AccountJourneySmokeTests.swift` signs in as the
staging contract user, asserts a file that was seeded over WebDAV before
launch shows up in the personal space, creates a folder from the app, deletes
it again and leaves staging clean. The expensive question was step 2, and
three cheaper routes were investigated first. All three are dead at this Pin,
so nobody has to re-tread them:

- **Reuse upstream's UI tests: there are none.** `ownCloudScreenshotsTests`
  survives only as a scheme and one `Pods_ownCloudScreenshotsTests.framework`
  file reference; `project.pbxproj` has no `com.apple.product-type.bundle.ui-testing`
  target at all, and the only test sources in the tree are unit tests
  (`ownCloudTests/Metadata`, `ownCloudAppTests`, `ownCloudAppFrameworkTests`).
  There is no harness to inherit and no upstream UI coverage a Bump could
  break.
- **Pre-seed an account from Branding: no key does that.**
  `bookmark.prepopulation` prepopulates the local DATABASE during setup
  (`doNot` / `split` / `streaming`, `doc/configuration.adoc`), not the
  account. The `branding.profile-*` keys lock the URL and skip the URL step,
  which is exactly what they already do here; they cannot supply credentials.
  Bookmarks live in `bookmarks.dat` (NSKeyedArchiver, app group container)
  with the auth data in the keychain (`OCBookmarkAuthenticationDataStorageKeychain`),
  so hand-writing one would be an archive-format dependency AND a simulator
  keychain write - implementation coupling of the worst kind.
- **Inject the callback URL: PKCE forbids it.** The app generates its own
  code verifier, so a `code` obtained out-of-band is bound to the harness's
  challenge and the app's token exchange fails. There is no way to hand the
  app a code it can spend.

So the browser sheet is driven, with the one setting that removes its worst
part: `authentication.browser-session-prefers-ephermal`. An ephemeral
`ASWebAuthenticationSession` skips the SpringBoard "wants to use ... to sign
in" consent alert, and the SDK reads that key straight from class settings
(`OCAuthenticationMethodOAuth2.m`, `webAuthenticationSession.prefersEphemeralWebBrowserSession`).

**Every class setting can be set at launch without rebuilding**, which is the
single most useful thing to know about testing this app:
`OCClassSettings.sharedSettings` registers `OCClassSettingsFlatSourceEnvironment`
with prefix `oc:`, so `app.launchEnvironment["oc:<flat.key>"] = "bool:true"`
(also `string:`, `int:`, `[a,b]`, `{json}`) overrides anything the
Branding.plist sets. XCUITest sets `launchEnvironment` on an app launched by
bundle identifier too.

Traps this cost, all confirmed against the real staging realm:

- **The realm's browser flow is IDENTITY-FIRST.** Page 1 is `login-username`
  (field `#username`, submit "Continue"), page 2 is `login` (field
  `#password`, submit "Sign in"). Posting both at once silently redisplays
  page 1 with no error message. The Android factory's test has the same two
  screens for the same reason.
- **The login page is a React app** (the Keycloakify `aity` theme), not
  server-rendered HTML: nothing matches `<form id="kc-form-login">` in the
  delivered markup, the form is built client-side from an embedded
  `kcContext`. Scraping it needs `kcContext.url.loginAction`.
- **The sheet's web content lives in `com.apple.SafariViewService`**, a
  separate process, so the test queries both that bundle id and the app under
  test and uses whichever has the fields.
- **`UIWebView` is NOT an escape hatch.** `authentication.browser-session-class`
  offers a `UIWebView` value, but it is `#if OC_FEATURE_AVAILABLE_UIWEBVIEW_BROWSER_SESSION`
  (default 0) and the implementation is literally `UIWebView`, removed from
  the iOS SDK long before Xcode 26. It cannot compile.
- **`CustomScheme` is a real escape hatch but needs a Patch.** The documented
  MDM route (AirWatch/MobileIron) hands the browser session to another app via
  a custom scheme and takes the callback back through
  `OCAuthenticationBrowserSessionCustomScheme.handleOpenURL:`. That class
  method is never called anywhere in the app at this Pin, so a helper-app
  based, fully deterministic login would need a Patch wiring it into the app's
  URL handling. Worth remembering if the sheet ever proves too flaky.

Before pushing anything in `smoke/`, run
**`scripts/check-smoke-swift.sh`**. `swiftc -parse` only parses - it never
resolves a name - so deleting a helper that is still called compiles clean
locally and fails on the Mac. That happened on 2026-08-27 and cost a round
trip on Raul's laptop for a missing `clear()`. The script type-checks the
smoke sources against hand-written XCTest/XCUITest stubs
(`smoke/typecheck/XCTestStubs.swift`) on Linux, and the `typecheck:smoke` CI
job runs the same command. Green there means "worth sending to the Mac", not
"this will pass": the stubs are hand-written and can drift, so when Xcode
disagrees about a signature, fix the stub too.

Operational notes for the lane:

- **DerivedData moved out of the materialised tree.** `materialize.sh` runs
  `git clean -fd` inside `build/upstream`, and upstream's `.gitignore` covers
  `build/` but not `build-simulator`, so the old `-derivedDataPath ../build-simulator`
  was deleted before every single build - every run was a cold compile of the
  whole Pin on a MacBook Air. It is now `<factory>/build/derived-simulator`,
  which survives and makes repeat runs incremental.
- **Each repeat starts from a fresh install.** The lane uninstalls and
  reinstalls between runs, because the account the previous run created lives
  in the app group container and a second run that starts logged in is not the
  test anyone wrote.
- `AITY_SMOKE_REPEAT` (default 1) measures the pass rate,
  `AITY_SMOKE_SKIP_BUILD=true` reuses the existing `.app`, `AITY_SMOKE_TESTS`
  narrows to one class. The `measure:smoke-flakiness` job wires all three.
- Without `AITY_CONTRACT_USER` / `AITY_CONTRACT_PASSWORD` the journey
  `XCTSkip`s itself and the login-screen smoke still runs, so a workstation
  without secrets gets a useful subset instead of a red run it cannot fix.

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

## Apple bootstrap, as it actually went (2026-08-27)

`bundle exec fastlane ios aity_bootstrap_apple` on the `macos` runner:

- 14 App IDs created (7 targets x 2 Environments), APP_GROUPS on all,
  ASSOCIATED_DOMAINS on the two parent apps.
- Team ID discovered from a bundle id's `seedId`: **Z3C9R3AHZ8** (now the
  protected group variable `AITY_TEAM_ID`). Nobody has to look it up.
- Distribution certificate R3FZ83C73U + 12 AppStore profiles created and
  pushed to `drive/certificates` on branch **master** (match's default).
- **App records cannot be created by API.** Apple answers
  `The resource 'apps' does not allow 'CREATE'`; only GET_COLLECTION,
  GET_INSTANCE and UPDATE. The lane reports the exact records to add by
  hand and continues - uploads fail until they exist.

App groups (`group.tech.aity.drive`, `group.tech.aity.drive.staging`) are
also outside the API. If a signed build fails on a missing
application-groups entitlement, create and associate them in the portal.

## The app icon comes from AppIcon.icon, not AppIcon.appiconset (2026-08-27)

Build 18 shipped with ownCloud's own app icon even though the lane
generated a full AppIcon.appiconset from our brand mark. Xcode 26 prefers
the Icon Composer asset when one exists, and the Pin ships
`ownCloud/Resources/AppIcon.icon` (owncloud-logo.svg on ownCloud blue,
referenced four times in project.pbxproj). Proof, from unpacking the
uploaded IPA: `Assets.car` contains `AppIcon_Assets/owncloud-logo` plus
the Icon Composer appearance variants; our appiconset was compiled and
ignored.

`scripts/generate-assets.py` now writes an `AppIcon.icon` per Environment -
same directory and icon.json path as upstream, so the project's file
references stay valid - with a white fill and our finished icon as the
single layer. The appiconset is still generated (harmless, and it is what
older toolchains would use). On a Bump, check whether upstream changed the
Icon Composer manifest schema.

Related, same day: the in-app `branding-logo.png` and
`branding-splashscreen-logo.png` were transparent, so the mark vanished on
any non-white surface; both are opaque white now. The sidebar link icon
stays transparent on purpose.

## De-branding: upstream's trademark outlives Branding.plist (2026-08-27)

The GPL gives us the code, not ownCloud's name, and the Pin leaves the
name in places no branding key reaches. Build 18, unpacked, carried:

- `Save to ownCloud` / `Share to ownCloud` in the iOS share sheet - these
  come from `APP_PRODUCT_NAME`, upstream's OWN branding hook, which
  defaults to `ownCloud`. Now set per target in `aity_apply_identity`.
- `Use ownCloud actions in Shortcuts.` translated into 23 languages.
- 140 translated strings inside `ownCloudSDK.framework` ("... is not an
  ownCloud instance").
- `CFBundleURLName` = `com.owncloud.com` / `.auth`.
- The app icon itself (see the Icon Composer entry above).

`scripts/debrand-strings.py` rewrites user-visible VALUES only - keys are
lookup identifiers, and rewriting them makes the UI show raw keys - across
`.strings`, `.stringsdict` and `Info.plist`, in both the legacy
`"k" = "v";` syntax and plist form. Two traps it taught us: the script's
own `/build/` exclusion made a CI run report `rewrote 0 values` while the
SDK stayed dirty (the materialised tree lives under `build/`), and the
tree path must come from `__dir__`, not `Dir.pwd`.

Left deliberately: bundle/executable/framework/class names (`ownCloud.app`,
`ownCloudSDK.framework`, `OC*`). They are the upstream software's internal
component names, never shown to a user, and renaming `PRODUCT_NAME` would
touch the whole project. Raul's call if that changes.

