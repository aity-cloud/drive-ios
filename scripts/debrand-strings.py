#!/usr/bin/env python3
"""Strip upstream's trademark from every USER-VISIBLE string in the tree.

The GPL gives us the code; it does not give us ownCloud's name. Upstream
leaves its brand in places the Overlay's Branding.plist never reaches, and
they are not obscure: the share sheet entry read "Save to ownCloud", the
Share Extension's localised display name read "Share to ownCloud" in 20+
languages, and "Use ownCloud actions in Shortcuts." shipped translated
everywhere (all found by unpacking build 18, 2026-08-27).

Rules:
  - VALUES only, never KEYS. A .strings key is the lookup identifier
    (usually the English source text); rewriting it breaks the lookup and
    the UI falls back to showing the raw key.
  - Info.plist display names and URL-type names are rewritten too.
  - Framework, executable and class names are LEFT ALONE deliberately:
    they are the upstream software's internal component names, not
    branding shown to a user, and renaming them would mean patching half
    the project.

Usage: debrand-strings.py <materialised-tree> <app-name> [bundle-id]
"""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

MARKS = re.compile(r"ownCloud", re.IGNORECASE)


def rewrite(value: str, app_name: str) -> str:
    return MARKS.sub(app_name, value)


# Keys whose value is an IDENTIFIER, not display text: rewriting them with
# the app name produced "com.Aity Drive.com" on the first run. They get the
# bundle id instead, keeping upstream's trailing component.
IDENTIFIER_KEYS = {"CFBundleURLName"}

# Rows we REPURPOSE rather than debrand. Settings > More shows a
# "Documentation" row whenever branding.url-documentation is set; ours points
# at the complete corresponding source, so the label says what the row does.
# Same text in every locale: it names a link, not a sentence to translate.
RELABEL = {"Documentation": "Source code & licences (GPLv3)"}


def walk_plist(obj, app_name: str, changed: list, path: str = "", bundle_id: str = ""):
    """Rewrite string VALUES in place; dict keys are never touched."""
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in IDENTIFIER_KEYS and isinstance(value, str) and MARKS.search(value):
                suffix = value.rsplit(".", 1)[-1] if "." in value else "app"
                obj[key] = f"{bundle_id}.{suffix}" if bundle_id else value
                changed.append(f"{path}/{key}")
            elif isinstance(value, str) and MARKS.search(value):
                obj[key] = rewrite(value, app_name)
                changed.append(f"{path}/{key}")
            else:
                walk_plist(value, app_name, changed, f"{path}/{key}", bundle_id)
    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            if isinstance(value, str) and MARKS.search(value):
                obj[index] = rewrite(value, app_name)
                changed.append(f"{path}[{index}]")
            else:
                walk_plist(value, app_name, changed, f"{path}[{index}]", bundle_id)


# Legacy .strings syntax:  "key" = "value";  - the format the SOURCE tree
# actually uses (Xcode compiles it to a binary plist at build time). Only
# the right-hand side is rewritten; the key is the lookup identifier.
LEGACY_PAIR = re.compile(r'^(?P<lead>\s*"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*")(?P<value>(?:[^"\\]|\\.)*)(?P<tail>";.*)$')


def process_legacy(path: Path, app_name: str) -> int:
    for encoding in ("utf-8", "utf-16"):
        try:
            text = path.read_text(encoding=encoding)
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
    else:
        return 0

    changed = 0
    out = []
    for line in text.splitlines(keepends=True):
        match = LEGACY_PAIR.match(line.rstrip("\n"))
        if match and (MARKS.search(match.group("value")) or match.group("key") in RELABEL):
            newline = "\n" if line.endswith("\n") else ""
            value = RELABEL.get(match.group("key")) or rewrite(match.group("value"), app_name)
            line = match.group("lead") + value + match.group("tail") + newline
            changed += 1
        out.append(line)

    if changed:
        path.write_text("".join(out), encoding=encoding)
    return changed


def process_xcstrings(path: Path, app_name: str) -> int:
    """String Catalogs (Xcode 15+): JSON, one entry per key, per-locale values.

    The main app moved to Localizable.xcstrings while the .lproj files this
    script was written for became leftovers - which is how "Use ownCloud
    actions in Shortcuts." kept shipping. The KEY is the English source text
    and is what iOS displays when a locale has no value, so a key that
    carries the mark also gets an explicit "en" value.
    """
    import json
    data = json.loads(path.read_text(encoding="utf-8"))
    strings = data.get("strings")
    if not isinstance(strings, dict):
        return 0
    changed = 0
    for key, entry in strings.items():
        wanted = RELABEL.get(key)
        locs = entry.setdefault("localizations", {})
        for loc in locs.values():
            unit = loc.get("stringUnit")
            if not isinstance(unit, dict):
                continue
            value = unit.get("value", "")
            new = wanted if wanted else (rewrite(value, app_name) if MARKS.search(value) else value)
            if new != value:
                unit["value"] = new
                unit["state"] = "translated"
                changed += 1
        if (wanted or MARKS.search(key)) and "en" not in locs:
            locs["en"] = {"stringUnit": {"state": "translated",
                                         "value": wanted or rewrite(key, app_name)}}
            changed += 1
    if changed:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return changed


def process(path: Path, app_name: str, bundle_id: str = "") -> int:
    try:
        with path.open("rb") as handle:
            data = plistlib.load(handle)
    except Exception:
        return process_legacy(path, app_name)

    changed: list[str] = []
    walk_plist(data, app_name, changed, "", bundle_id)
    if not changed:
        return 0

    fmt = plistlib.FMT_XML
    with path.open("rb") as handle:
        if handle.read(8) == b"bplist00":
            fmt = plistlib.FMT_BINARY
    with path.open("wb") as handle:
        plistlib.dump(data, handle, fmt=fmt)
    return len(changed)


def main() -> None:
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    tree = Path(sys.argv[1])
    app_name = sys.argv[2]
    bundle_id = sys.argv[3] if len(sys.argv) == 4 else ""
    if not tree.is_dir():
        print(f"debrand-strings: {tree} is not a directory", file=sys.stderr)
        sys.exit(1)

    total_files = 0
    total_values = 0
    for pattern in ("**/*.xcstrings",):
        for path in tree.glob(pattern):
            if "/build/" in str(path):
                continue
            n = process_xcstrings(path, app_name)
            if n:
                total_values += n
                total_files += 1
                print(f"debrand-strings: {path.relative_to(tree)}: {n} value(s)")
    for pattern in ("**/*.strings", "**/*.stringsdict", "**/Info.plist"):
        for path in tree.glob(pattern):
            # No "/build/" skip here: the materialised tree IS under build/,
            # and that filter silently made a CI run rewrite 0 files while
            # the SDK framework kept 140 translated ownCloud strings.
            if "/.git/" in str(path):
                continue
            count = process(path, app_name, bundle_id)
            if count:
                total_files += 1
                total_values += count
                print(f"debrand: {path.relative_to(tree)} ({count})")

    print(f"debrand: rewrote {total_values} values in {total_files} files -> {app_name!r}")
    if total_values == 0:
        print("debrand: nothing to rewrite (already clean, or the tree moved)")


if __name__ == "__main__":
    main()
