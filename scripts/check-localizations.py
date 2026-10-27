#!/usr/bin/env python3
"""Fails when a string in the app has no translation for a language.

Reads the XLIFF that `xcodebuild -exportLocalizations` extracts from the code and the string
catalogs, so a string added in Swift without a translation is caught even if the catalog was
never opened in Xcode.

Usage: check-localizations.py LOCALIZATION_EXPORT_DIR LANGUAGE...
"""
import pathlib
import sys
import xml.etree.ElementTree as ElementTree

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


def missing_translations(xliff: pathlib.Path) -> tuple[int, list[str]]:
    missing = []
    checked = 0
    for unit in ElementTree.parse(xliff).getroot().iterfind(".//x:trans-unit", NS):
        if unit.get("translate") == "no":
            continue
        checked += 1
        source = unit.findtext("x:source", default="", namespaces=NS)
        target = unit.find("x:target", NS)
        state = target.get("state") if target is not None else None
        if target is None or not (target.text or "").strip() or state in ("new", "needs-translation"):
            missing.append(f"{unit.get('id')!r} (source: {source!r})")
    return checked, missing


def main() -> int:
    export_dir = pathlib.Path(sys.argv[1])
    failed = False
    for language in sys.argv[2:]:
        xliffs = list(export_dir.glob(f"{language}.xcloc/Localized Contents/*.xliff"))
        if not xliffs:
            print(f"error: no XLIFF exported for {language}")
            return 1
        for xliff in xliffs:
            checked, missing = missing_translations(xliff)
            if checked == 0:
                failed = True
                print(f"error: {xliff.name} contains no strings; the export didn't pick up the code")
                continue
            if missing:
                failed = True
                print(f"error: {len(missing)} string(s) without a {language} translation in {xliff.name}:")
                for item in missing:
                    print(f"  - {item}")
            else:
                print(f"{xliff.name}: all {checked} strings have a {language} translation")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
