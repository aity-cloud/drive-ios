#!/usr/bin/env python3
"""Add the Factory's own languages to upstream's String Catalogs.

Upstream ships its translations in Xcode String Catalogs (*.xcstrings) and
takes new ones only through Transifex, at 75% coverage. Romanian is not
there, so the Factory keeps its translation in l10n/<locale>/, one JSON
object per catalog ({catalog key: translated value}) at the catalog's path
with .json for .xcstrings, and writes it into the catalog as an ordinary
localization. Xcode compiles every language a catalog holds into its
.lproj, which is what makes iOS offer the app in that language.

Fails (exit 1) when a translation file has no catalog upstream, or when a
value's format specifiers differ from the English source (a wrong %@ is a
crash, not a typo). Warns for keys upstream dropped and for strings that
have no translation yet: a Bump must not wait on translation, the warning
is the list for the next maintenance pass.

Usage: localize.py <materialised-tree>
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
L10N = REPO_ROOT / "l10n"

SPECIFIER = re.compile(r"%(\d+\$)?[-+ #0]*\d*(\.\d+)?(ll|l|h|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSp%]")


def specifiers(text: str) -> list[str]:
    return sorted(m.group(0) for m in SPECIFIER.finditer(text))


def source_text(key: str, entry: dict) -> str:
    unit = entry.get("localizations", {}).get("en", {}).get("stringUnit", {})
    return unit.get("value", key)


def apply(catalog: Path, locale: str, translations: dict[str, str]) -> tuple[list[str], list[str], list[str]]:
    data = json.loads(catalog.read_text(encoding="utf-8"))
    strings = data["strings"]
    errors, stale, missing = [], [], []
    for key, value in translations.items():
        entry = strings.get(key)
        if entry is None:
            stale.append(key)
            continue
        if specifiers(value) != specifiers(source_text(key, entry)):
            errors.append(f"{key!r}: {specifiers(source_text(key, entry))} in English, {specifiers(value)} in {locale}")
            continue
        entry.setdefault("localizations", {})[locale] = {"stringUnit": {"state": "translated", "value": value}}
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is not False and key not in translations:
            missing.append(key)
    if not errors:
        catalog.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return errors, stale, missing


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    tree = Path(sys.argv[1])
    failed = False
    for source in sorted(L10N.glob("*/**/*.json")):
        locale = source.relative_to(L10N).parts[0]
        rel = source.relative_to(L10N / locale).with_suffix(".xcstrings")
        catalog = tree / rel
        if not catalog.is_file():
            print(f"localize: FAIL - {rel} does not exist upstream ({source.relative_to(REPO_ROOT)})", file=sys.stderr)
            failed = True
            continue
        errors, stale, missing = apply(catalog, locale, json.loads(source.read_text(encoding="utf-8")))
        for line in errors:
            print(f"localize: FAIL - {rel} {line}", file=sys.stderr)
        for key in stale:
            print(f"localize: warning - {rel} [{locale}] no longer upstream: {key!r}")
        for key in missing:
            print(f"localize: warning - {rel} [{locale}] untranslated: {key!r}")
        failed = failed or bool(errors)
        print(f"localize: {rel} [{locale}] {'NOT WRITTEN' if errors else 'written'}, "
              f"{len(missing)} untranslated, {len(stale)} stale")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
