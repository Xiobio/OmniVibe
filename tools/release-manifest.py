"""Inventory build output without deleting assets or modifying user installations."""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path


def classify(path: str) -> str:
    lower = path.lower()
    if lower.endswith(('.prompt.md', '.validation.json')) or '/tests/' in lower:
        return 'development-reference'
    if lower.endswith(('.md', '.html')):
        return 'documentation-or-gallery'
    if lower.startswith(('skins/', 'themes/')):
        return 'theme-resource'
    if lower.startswith('scripts/'):
        return 'integration-script'
    return 'application'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    app, output = args.app.resolve(strict=True), args.output.resolve()
    if not (app / 'CodeManager.exe').is_file():
        parser.error('--app must contain the built CodeManager.exe')
    if output.is_relative_to(app):
        parser.error('--output must be outside the application directory')
    files = []
    totals: Counter[str] = Counter()
    for path in sorted(app.rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(app).as_posix()
        kind = classify(relative)
        size = path.stat().st_size
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        files.append(dict(path=relative, bytes=size, sha256=digest, category=kind))
        totals[kind] += size
    report = dict(version=1, file_count=len(files), total_bytes=sum(totals.values()),
                  bytes_by_category=dict(totals), files=files,
                  scope='Build-output inventory, not a redistribution license or minimal runtime dependency manifest.')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('file_count', 'total_bytes', 'bytes_by_category')}))


if __name__ == '__main__':
    main()
