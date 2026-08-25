# Patches

**Inventory: EMPTY. Zero patches - the target state (meta ADR 0001).**

Everything Aity Drive for iOS needs is expressed through upstream's own
Branding surface (`Branding.plist`, `branding-assets/`, the fastlane
branding flow) - see `UPSTREAM.md`.

## The bar for adding a patch

A patch is accepted only when the app is **not shippable without it** and
Branding cannot express it. Every patch:

- lives in `patches/*.patch` (applied by `scripts/materialize.sh` with
  `git apply`, in lexical order),
- gets a hunk-by-hunk entry here: what it changes, why Branding cannot,
  the upstream issue/PR asking to make it Branding-expressible,
- is re-validated on every Bump (`materialize.sh` fails the pipeline if a
  patch stops applying).

## Near-misses recorded (things that looked like patches but are not)

- **No UI-test target at the Pin**: solved with the standalone
  `smoke/` xcodegen project instead of patching `ownCloud.xcodeproj`.
- **Hardcoded `com.owncloud.ownCloudAppShared` framework id in upstream's
  `build_ipa_in_house`**: solved by transcribing the lane in our
  `fastlane/Fastfile` (recipe, not a source patch) with the shared
  framework id parameterised.
