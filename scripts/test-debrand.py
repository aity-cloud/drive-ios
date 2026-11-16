#!/usr/bin/env python3
"""Self-test for debrand-strings.py on a tree whose absolute path contains /build/, as in CI."""

import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("debrand-strings.py")

with tempfile.TemporaryDirectory() as tmp:
    tree = Path(tmp) / "build" / "upstream"
    (tree / "Share").mkdir(parents=True)
    (tree / "Share" / "InfoPlist.xcstrings").write_text(json.dumps({"sourceLanguage": "en", "strings": {
        "CFBundleDisplayName": {"localizations": {
            "en": {"stringUnit": {"state": "translated", "value": "Share to ownCloud"}},
            "ro": {"stringUnit": {"state": "translated", "value": "Partajează în ownCloud"}}}},
        "NSHumanReadableCopyright": {"localizations": {
            "en": {"stringUnit": {"state": "translated", "value": "Copyright © 2023 ownCloud GmbH."}}}},
        "Documentation": {"localizations": {
            "ro": {"stringUnit": {"state": "translated", "value": "Documentație"}}}},
    }}))
    with (tree / "Share" / "Info.plist").open("wb") as handle:
        plistlib.dump({"CFBundleDisplayName": "ownCloud", "NSHumanReadableCopyright": "© ownCloud GmbH"}, handle)

    subprocess.run([sys.executable, str(SCRIPT), str(tree), "Aity Drive", "tech.aity.drive"], check=True,
                   stdout=subprocess.DEVNULL)

    strings = json.loads((tree / "Share" / "InfoPlist.xcstrings").read_text())["strings"]
    value = lambda key, loc: strings[key]["localizations"][loc]["stringUnit"]["value"]
    assert value("CFBundleDisplayName", "en") == "Share to Aity Drive", strings
    assert value("CFBundleDisplayName", "ro") == "Partajează în Aity Drive", strings
    assert value("NSHumanReadableCopyright", "en") == "Copyright © 2023 ownCloud GmbH.", strings
    assert value("Documentation", "ro") == "Cod sursă și licențe (GPLv3)", strings
    with (tree / "Share" / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    assert info == {"CFBundleDisplayName": "Aity Drive", "NSHumanReadableCopyright": "© ownCloud GmbH"}, info
print("test-debrand: ok")
