#!/usr/bin/env python3
"""Validate every plist this Factory authors, without Xcode.

Two layers:

1. Syntax: each authored .plist parses with plistlib (the same XML plist
   format the app's NSPropertyListSerialization reads).

2. Environment parity: the production and staging Branding.plist must have
   the IDENTICAL key set, and the values may differ only in the keys listed
   in ENV_SPECIFIC_KEYS. This is the drift tripwire for the copy-based
   overlay (plists cannot be merged, so each Environment carries a full
   file). It also pins the identity-table values so a typo in a redirect
   URI or bundle-adjacent key fails lint instead of Mac day.

Run from anywhere: paths are resolved relative to the repo root.
"""

import plistlib
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

PROD = REPO_ROOT / "overlay/production/ownCloud/Resources/Theming/Branding.plist"
STAG = REPO_ROOT / "overlay/staging/ownCloud/Resources/Theming/Branding.plist"

# Keys allowed (and required) to differ between the Environments, with the
# exact values the identity table in meta/specs/aity-drive-v1.md fixes.
ENV_SPECIFIC_KEYS = {
    "branding.app-name": ("Aity Drive", "Aity Drive (staging)"),
    "branding.profile-url": ("https://drive.aity.tech", "https://drive.aity.works"),
    "branding.profile-bookmark-name": ("Aity Drive", "Aity Drive (staging)"),
    "authentication-oauth2.oidc-redirect-uri": (
        "aitydrive://ios.aity.tech",
        "aitydrive-staging://ios.aity.works",
    ),
    "authentication-oauth2.oa2-redirect-uri": (
        "aitydrive://ios.aity.tech",
        "aitydrive-staging://ios.aity.works",
    ),
    "build.custom-app-scheme": ("aitydrive-app", "aitydrive-staging-app"),
    "build.custom-auth-scheme": ("aitydrive", "aitydrive-staging"),
    "build.app-group-identifier": (
        "group.tech.aity.drive",
        "group.tech.aity.drive.staging",
    ),
}

# Shared values worth pinning explicitly (identity + licence stance).
PINNED_COMMON = {
    "branding.organization-name": "Aity",
    "branding.profile-allow-url-configuration": False,
    "authentication-oauth2.oa2-client-id": "drive-ios",
    "authentication-oauth2.oa2-client-secret": "",
    "connection.allowed-authentication-methods": ["com.owncloud.openid-connect"],
    "branding.sidebar-links$[0].url": "https://github.com/aity-cloud/drive-ios",
    "branding.theme-definitions$[0].lightBrandColor": "#b80818",
    "build.flags": "DISABLE_APPSTORE_LICENSING DISABLE_PLAIN_HTTP",
}


def fail(msg: str) -> None:
    print(f"check-plists: FAIL - {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    plists = sorted(
        p
        for p in REPO_ROOT.rglob("*.plist")
        if "build" not in p.relative_to(REPO_ROOT).parts
    )
    if not plists:
        fail("no plists found - repository layout changed?")

    parsed = {}
    for path in plists:
        try:
            with path.open("rb") as fh:
                parsed[path] = plistlib.load(fh)
        except Exception as exc:  # noqa: BLE001 - report any parse failure
            fail(f"{path.relative_to(REPO_ROOT)} does not parse: {exc}")
        print(f"check-plists: parsed {path.relative_to(REPO_ROOT)}")

    for required in (PROD, STAG):
        if required not in parsed:
            fail(f"missing {required.relative_to(REPO_ROOT)}")

    prod, stag = parsed[PROD], parsed[STAG]

    if set(prod) != set(stag):
        only_prod = sorted(set(prod) - set(stag))
        only_stag = sorted(set(stag) - set(prod))
        fail(
            "Branding.plist key sets differ between environments: "
            f"only in production {only_prod}, only in staging {only_stag}"
        )

    for key, prod_value in prod.items():
        stag_value = stag[key]
        if key in ENV_SPECIFIC_KEYS:
            want_prod, want_stag = ENV_SPECIFIC_KEYS[key]
            if prod_value != want_prod:
                fail(f"production {key} = {prod_value!r}, identity table says {want_prod!r}")
            if stag_value != want_stag:
                fail(f"staging {key} = {stag_value!r}, identity table says {want_stag!r}")
        elif prod_value != stag_value:
            fail(
                f"{key} differs between environments ({prod_value!r} vs {stag_value!r}) "
                "but is not in ENV_SPECIFIC_KEYS - either fix the plists or, if the "
                "difference is intended, add the key to scripts/check-plists.py"
            )

    for key, want in PINNED_COMMON.items():
        if key not in prod:
            fail(f"pinned key {key} missing from Branding.plist")
        if prod[key] != want:
            fail(f"{key} = {prod[key]!r}, expected {want!r}")

    print(
        "check-plists: OK - "
        f"{len(plists)} plists parse, Branding.plist environments in sync, "
        f"{len(ENV_SPECIFIC_KEYS)} environment keys and {len(PINNED_COMMON)} pinned keys match the identity table"
    )


if __name__ == "__main__":
    main()
