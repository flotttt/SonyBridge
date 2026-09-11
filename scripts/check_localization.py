#!/usr/bin/env python3
"""Every tr("…") / NSLocalizedString("…") key must have a French translation, and every French key must be used."""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAC = ROOT / "Client" / "macos"
STRINGS = MAC / "fr.lproj" / "Localizable.strings"
LITERAL = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = [re.compile(r"\btr\(" + LITERAL + r"\)"), re.compile(r"NSLocalizedString\(@?" + LITERAL)]

def unescape_source_literal(key):
    r"""Unescape source string literals: \n → newline, \t → tab, and any other \X → X."""
    def replace_escape(match):
        char = match.group(1)
        escapes = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', '\\': '\\'}
        return escapes.get(char, char)
    return re.sub(r"\\(.)", replace_escape, key)

french = set(json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(STRINGS)])))
used = set()
for path in sorted(MAC.rglob("*.swift")) + sorted(MAC.rglob("*.mm")):
    text = path.read_text(encoding="utf-8")
    for pattern in PATTERNS:
        used.update(unescape_source_literal(key) for key in pattern.findall(text))

missing = sorted(used - french)
unused = sorted(french - used)
for key in missing:
    print(f"missing French translation: {key!r}")
for key in unused:
    print(f"unused French key: {key!r}")
if missing or unused:
    sys.exit(1)
print(f"Localization: {len(used)} keys, all translated")
