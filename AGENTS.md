# Agent rules for drive/ios

The iOS Factory of the Aity Drive Clients: Pin + Overlay + Patches + CI on
top of `owncloud/ios-app`. The subgroup-wide rules in `../meta/AGENTS.md`
apply in full (overlay only, trademark, CI publishes / humans promote,
both Environment builds, secrets, mirror, response targets); read
`../meta/specs/aity-drive-v1.md` for the identity table before changing
anything identity-adjacent.

Repo-specific rules:

- **Never commit `build/`** - the materialised upstream tree is scratch.
  `scripts/materialize.sh <production|staging>` recreates it; `--check`
  is the Bump tripwire.
- **The two `Branding.plist` files are a contract**: full copies per
  Environment, key sets identical, differences whitelisted in
  `scripts/check-plists.py`. Touch a plist -> run the script -> update the
  whitelist consciously (it mirrors the spec's identity table).
- **`fastlane/Fastfile` transcribes upstream's `build_ipa_in_house`**
  (why: header comment there). On every Bump, diff upstream's lane and
  fold changes in. Do not "simplify" the transcription away from
  upstream's action order.
- **Branding assets are generated, never hand-edited**
  (`scripts/generate-assets.py` from `../meta/brand/logo.svg`).
- **Zero patches is the target**; a new patch needs the PATCHES.md bar
  ("not shippable without it") and an inventory entry.
- **Nothing Xcode is verifiable here until the `macos` runner exists** -
  keep MAINTAINING.md's UNVERIFIED list honest: move items out only with
  a real run on the Mac, never by assertion.
- Commit identity `raul@aity.ro`. Plain dashes only, never em dashes.
  AGENTS.md is canonical; CLAUDE.md is a symlink to it.
