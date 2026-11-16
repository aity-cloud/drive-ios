#!/usr/bin/env python3
"""Self-test for localize.py: a translation lands, a broken specifier does not."""

import importlib.util
import json
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("localize", Path(__file__).with_name("localize.py"))
localize = importlib.util.module_from_spec(spec)
spec.loader.exec_module(localize)

catalog_data = {"sourceLanguage": "en", "version": "1.0", "strings": {
    "Delete %@": {},
    "rename": {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "%1$@ renamed to %2$@"}}}},
    "Untranslated": {},
    "Brand": {"shouldTranslate": False},
}}

with tempfile.TemporaryDirectory() as tmp:
    catalog = Path(tmp) / "Localizable.xcstrings"
    catalog.write_text(json.dumps(catalog_data))
    errors, stale, missing = localize.apply(catalog, "ro", {
        "Delete %@": "Șterge %@", "rename": "%1$@ a fost redenumit %2$@", "Gone": "Dispărut"})
    assert (errors, stale, missing) == ([], ["Gone"], ["Untranslated"]), (errors, stale, missing)
    written = json.loads(catalog.read_text())["strings"]
    assert written["Delete %@"]["localizations"]["ro"]["stringUnit"]["value"] == "Șterge %@"
    assert written["rename"]["localizations"]["en"]["stringUnit"]["value"] == "%1$@ renamed to %2$@"

    catalog.write_text(json.dumps(catalog_data))
    errors, _, _ = localize.apply(catalog, "ro", {"Delete %@": "Șterge %ld", "rename": "%@ redenumit %@"})
    assert len(errors) == 2, errors
    assert "ro" not in json.loads(catalog.read_text())["strings"]["Delete %@"].get("localizations", {})

assert localize.specifiers("%1$@ of %2$ld (%.1f%%)") == sorted(["%1$@", "%2$ld", "%.1f", "%%"])
assert localize.specifiers("{{count}} of %@") == sorted(["{{count}}", "%@"])
assert localize.specifiers("Open {{app.name }}") == ["{{app.name }}"]
print("test-localize: ok")
