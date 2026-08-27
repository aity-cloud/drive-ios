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

What the first real runs established (2026-08-27), so nobody re-derives it:

- **The OIDC login works end to end and takes about 13 seconds.** Intro ->
  "Open login page" -> the SafariViewService sheet -> email page -> password
  page -> sheet closes -> "Account setup complete" -> Done. No SpringBoard
  consent alert appears, which is `browser-session-prefers-ephermal` doing
  its job.
- **Both login pages are submitted with the KEYBOARD RETURN KEY, not a
  button tap.** The submit button of the Keycloakify pages sits below the
  fold on a phone-sized sheet, and XCUITest refuses to tap an element it
  considers not hittable. The button tap (plus a swipe) is still there as the
  fallback.
- **After login the app shows the account SIDEBAR, not the file list.** On a
  phone the split view is collapsed, so "Drive Contract" (the personal space
  - on oCIS its name is the user's DISPLAY NAME, not the word "Personal"),
  Spaces, Shares, Recents and Available Offline are what is on screen, and
  the files are one push away. The account header repeats the space's name,
  so tapping the first static text with that name taps the header and nothing
  happens; tap the CELL.
- **`XCUIApplication.debugDescription` is useless in a failure message**: once
  the app is not attached it prints the query chain, not the tree. Collect the
  labels of static texts, buttons and cells instead - which is what
  `visibleLabels` does, and what turned the sidebar problem from a guess into
  a one-line diagnosis.
- **Each test class needs its own xcodebuild invocation and its own fresh
  install.** `LoginScreenSmokeTests` asserts the FIRST-RUN screen, and the
  journey leaves the app signed in, so running them together reported the
  login-screen smoke as broken when it was not.

### The app terminates after opening the personal space (FIXED, 2026-08-27)

Was: connecting an account killed the app with SIGABRT a few seconds after
the personal space opened, 0 runs out of 5.

The crash report (host `~/Library/Logs/DiagnosticReports`, read with the
`diagnose:crash-reports` job) named it exactly:

```
EXC_CRASH (SIGABRT), uncaught ObjC exception
  Foundation    -[NSAssertionHandler handleFailureInMethod:...]
  FileProvider  -[NSFileProviderManager documentStorageURL]
  ownCloudSDK   +[OCVault storageRootURL]
  ownCloudApp   -[OCFileProviderServiceSession initWithBookmark:]
  ownCloudApp   -[OCFileProviderServiceStandby initWithCore:]
  ownCloudAppShared AccountConnection.startFPServiceStandbyIfNotRunning()
  ownCloudAppShared AccountConnection.connect(consumer:completion:)
```

Connecting an account starts the File Provider standby, which asks
`NSFileProviderManager.documentStorageURL` for the shared container.
That API ASSERTS when the app group is not available - and the smoke was
building with `CODE_SIGNING_ALLOWED=NO`, which strips the entitlements,
so the container did not exist. **The app was never broken; the test
build was.** Nothing about it was app-specific, which is why it looked
like a race: it depended only on how far the connect sequence got before
the standby kicked in.

Fixed by ad-hoc signing the simulator build (`CODE_SIGN_IDENTITY='-'`,
`CODE_SIGNING_REQUIRED=NO`) so the entitlements - and therefore the app
group container - are real. Still needs no Apple account. First green run
of `AccountJourneySmokeTests` followed immediately, including the
create-folder / delete-folder half that had never executed.

Lesson worth keeping: an unsigned simulator build is NOT a faithful
approximation of the shipped app. Anything that touches app groups,
keychain groups or File Provider behaves differently, and it fails as an
assert rather than a diagnosable error.

## Renaming the embedded frameworks crashes the shipped app (fixed 2026-08-27)

The device build died with `EXC_BREAKPOINT` a few seconds after an account
connected - build 21, iPhone 18,4, iOS 26.6 - while the simulator smoke was
5/5 green. Symbolicated against the archive's dSYM:

```
AccountConnection.status.didSet
  AccountController.account(connection:changedStatusTo:)  AccountController.swift:223
  AccountController.composeItemsDataSource()              AccountController.swift:455
  dispatch_once: one-time initialization of cloudAvailableOfflineStatusIcon
```

That icon comes from `Bundle.sharedAppBundle`, and upstream defines it as

```swift
private let _sharedAppBundle = Bundle(identifier: "com.owncloud.ownCloudAppShared")
public extension Bundle {
    static var sharedAppBundle : Bundle { return _sharedAppBundle! }
}
```

a HARDCODED id, force-unwrapped. `aity_ids` was renaming the two embedded
frameworks to `<app-id>.framework` / `.shared` purely so no bundle id of
ours carried the upstream trademark. That made the lookup nil, and the
first icon or localised string drawn from the shared bundle trapped.

Both frameworks now keep upstream's ids. They are internal - no user sees a
framework bundle id - which is the same line already drawn for the
executable name `ownCloud`. If a future Bump renames or removes that
constant, this becomes safe to revisit; grep for `Bundle(identifier:` in
the Pin (v12.7.0 has exactly one).

**Why the simulator never caught it:** `build_simulator_smoke` runs
`aity_apply_identity` but NOT `aity_apply_signing`, and the framework ids
are rewritten in the SIGNING lane. So the simulator built upstream's ids
and worked, while every signed store build was broken. Any future identity
change that lives only in the signing path has the same blind spot - the
account-journey smoke cannot see it.

