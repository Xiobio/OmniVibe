#!/usr/bin/env python3
"""Review/wrap Chinese literals in explicitly chosen presentation files.

This is a developer migration utility, not a build step. It never scans or
rewrites the workspace automatically. Raw enum values and existing L10n calls
are retained. The Swift-aware catalogue lexer preserves interpolation code,
comments, raw/multiline literals, and nested string boundaries. Review the diff
and separately handle dynamic user data and presentation helpers afterwards.
"""
from pathlib import Path
import argparse
import importlib.util
import re

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("localization_catalog", Path(__file__).with_name("localization-catalog.py"))
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


def proposed(source):
    insertions = {}
    count = 0
    for literal in catalog.swift_literals(source):
        start, end = literal["start"], literal["end"]
        prefix = source[:start]
        line = prefix.rsplit("\n", 1)[-1]
        if re.search(r"L10n\.(?:text|format)\s*\(\s*$", prefix[-100:]): continue
        if re.match(r"\s*case\s+[^\n]*=\s*$", line): continue
        insertions.setdefault(start, []).append("L10n.text(")
        insertions.setdefault(end, []).append(")")
        count += 1
    result = source
    for position in sorted(insertions, reverse=True):
        result = result[:position] + "".join(insertions[position]) + result[position:]
    return result, count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write only the explicitly supplied files")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    for name in args.files:
        path = (ROOT / name).resolve()
        allowed = ROOT / "src/OmniVibeMac/Sources/OmniVibeMac/UI"
        if not path.is_relative_to(allowed) or path.suffix != ".swift":
            parser.error("Only explicitly selected macOS UI Swift files are allowed")
        updated, count = proposed(path.read_text())
        if args.write and count: path.write_text(updated)
        print(f"{path.relative_to(ROOT)}: {count} literal wrappers" + (" written" if args.write else " proposed"))


if __name__ == "__main__": main()
