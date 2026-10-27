#!/usr/bin/env python3
"""Read Swift literals and report localization coverage; never rewrites Swift.

Chinese source is the stable key. Swift interpolation becomes %@ in the
catalogue, while its expression remains untouched in the source inventory.
Comments, nested strings, raw strings and multiline strings are recognized.
Run --check after adding user-facing text, or --inventory to review contexts.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[2]
SOURCES = REPO / "src/OmniVibeMac/Sources"
CATALOG = SOURCES / "OmniVibeMac/Resources/Localization/en.json"
HAN = re.compile(r"[\u3400-\u9fff]")


def swift_literals(text: str, include_all: bool = False):
    records = []

    def skip_comment(i):
        if text.startswith("//", i):
            end = text.find("\n", i + 2)
            return len(text) if end < 0 else end
        if text.startswith("/*", i):
            i += 2
            depth = 1
            while i < len(text) and depth:
                if text.startswith("/*", i): depth += 1; i += 2
                elif text.startswith("*/", i): depth -= 1; i += 2
                else: i += 1
            return i
        return None

    def string_start(i):
        j = i
        while j < len(text) and text[j] == "#": j += 1
        if j >= len(text) or text[j] != '"': return None
        mark = '"""' if text.startswith('"""', j) else '"'
        return j - i, mark, j + len(mark)

    def interpolation(i):
        start = i
        depth = 1
        while i < len(text) and depth:
            comment = skip_comment(i)
            if comment is not None: i = comment; continue
            prefix = string_start(i)
            if prefix:
                _, i = string(i, prefix)
                continue
            if text[i] == "(": depth += 1
            elif text[i] == ")": depth -= 1
            i += 1
        return text[start:i - 1], i

    def string(start, prefix):
        hashes, mark, i = prefix
        terminator = mark + "#" * hashes
        escape = "\\" + "#" * hashes
        pieces, expressions = [], []
        while i < len(text):
            if text.startswith(terminator, i):
                i += len(terminator)
                break
            if text.startswith(escape, i):
                j = i + len(escape)
                if j < len(text) and text[j] == "(":
                    expression, i = interpolation(j + 1)
                    pieces.append("%@"); expressions.append(expression)
                    continue
                if j < len(text) and text[j] in 'nrt0"\\':
                    pieces.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0", '"': '"', "\\": "\\"}[text[j]])
                    i = j + 1; continue
                unicode_escape = re.match(r"u\{([0-9a-fA-F]+)\}", text[j:])
                if unicode_escape:
                    pieces.append(chr(int(unicode_escape.group(1), 16)))
                    i = j + len(unicode_escape.group(0)); continue
                pieces.append(escape); i = j; continue
            pieces.append(text[i]); i += 1
        value = "".join(pieces)
        if mark == '"""':
            value = value.strip("\n")
        if include_all or HAN.search(value):
            records.append({"line": text.count("\n", 0, start) + 1,
                            "source": value, "expressions": expressions,
                            "start": start, "end": i})
        return value, i

    i = 0
    while i < len(text):
        comment = skip_comment(i)
        if comment is not None: i = comment; continue
        prefix = string_start(i)
        if prefix: _, i = string(i, prefix)
        else: i += 1
    return records


def inventory():
    records = []
    for target in ["OmniVibeMac", "OmniVibeCore"]:
        for path in sorted((SOURCES / target).rglob("*.swift")):
            if path.name == "Localization.swift": continue
            for record in swift_literals(path.read_text()):
                records.append({"file": str(path.relative_to(REPO)), **record})
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--inventory", action="store_true")
    args = parser.parse_args()
    rows = inventory()
    if args.inventory:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0
    data = json.loads(CATALOG.read_text())
    entries = data["translations"]
    missing = sorted({row["source"] for row in rows} - set(entries))
    report = {"source_literals": len(rows), "unique_source_keys": len({r["source"] for r in rows}),
              "catalogue_keys": len(entries), "missing": missing}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if args.check and missing else 0


if __name__ == "__main__":
    sys.exit(main())
