"""Read-only repository inventory and source/asset checks for a review snapshot.

Run from any directory. Evidence is local by default; no runtime user data is read.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
from importlib import metadata
import json
from pathlib import Path
import platform
import re
import subprocess
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = {'.cs', '.xaml', '.csproj', '.ps1', '.py', '.hlsl'}
RASTER = {'.png', '.jpg', '.jpeg', '.gif', '.ico', '.apng'}
CONFIGURATIONS = (
    'skins/catalog.json', 'skins/loadouts/suites-v1/catalog.json',
    'skins/audio/manifest.json', 'themes/windows-terminal/skins.json',
    'themes/windows-terminal/classic-palettes.json', 'src/CodeManager/app.manifest',
)


def git(*args: str) -> str:
    return subprocess.check_output(['git', '-C', str(ROOT), *args]).decode('utf-8').strip()


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []

    def handle_starttag(self, tag, attrs):
        self.refs.extend(v for k, v in attrs if k in ('src', 'href', 'poster') and v)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'artifacts/code-review/snapshot.json')
    parser.add_argument('--decode-raster', action='store_true', help='Fully decode each raster first frame; use native GIF checks separately.')
    args = parser.parse_args()
    names = sorted(set(git('ls-files', '--cached', '--others', '--exclude-standard', '-z').split('\0')))
    paths = [ROOT/n for n in names if n and (ROOT/n).is_file()]
    sizes = {p.relative_to(ROOT).as_posix(): p.stat().st_size for p in paths}
    hashes = {}
    lines = Counter()
    issues = []
    checked = Counter()
    raster_bytes = 0
    secret_hits = []
    # Strong token formats only. Never emit or persist matched credential values.
    tokens = {
        'github_token': re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}\b'),
        'private_key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
        'openai_key': re.compile(r'\bsk-(?:proj-)?[A-Za-z0-9_-]{40,}\b'),
        'literal_secret': re.compile(r'''(?i)(?:app_secret|client_secret|api_key|access_token)["']?\s*[:=]\s*["'][A-Za-z0-9_-]{24,}["']'''),
    }
    for p in paths:
        rel = p.relative_to(ROOT).as_posix()
        suffix = p.suffix.lower()
        if suffix in SOURCE:
            content = p.read_bytes()
            hashes[rel] = hashlib.sha256(content).hexdigest()
            text = content.decode('utf-8-sig')
            lines[suffix] += len(text.splitlines())
            if suffix == '.py':
                checked['python'] += 1
                try:
                    ast.parse(text, filename=rel)
                except SyntaxError as e:
                    issues.append({'kind': 'python', 'file': rel, 'line': e.lineno, 'error': e.msg})
            if suffix in ('.csproj', '.xaml'):
                checked['xml'] += 1
                try:
                    ElementTree.fromstring(text)
                except ElementTree.ParseError as e:
                    issues.append({'kind': 'xml', 'file': rel, 'error': str(e)})
        if suffix == '.svg':
            checked['svg'] += 1
            try:
                ElementTree.parse(p)
            except ElementTree.ParseError as e:
                issues.append({'kind': 'svg', 'file': rel, 'error': str(e)})
        if suffix in RASTER:
            checked['raster'] += 1
            raster_bytes += sizes[rel]
            try:
                with Image.open(p) as im:
                    if args.decode_raster:
                        im.load()
                    assert im.width > 0 and im.height > 0
            except (OSError, ValueError, AssertionError) as e:
                issues.append({'kind': 'raster', 'file': rel, 'error': str(e)})
        if suffix in ('.md', '.html'):
            text = p.read_text(encoding='utf-8-sig')
            if suffix == '.html':
                links = Links()
                links.feed(text)
                refs = links.refs
            else:
                refs = re.findall(r'\]\(([^\s)]+)\)', text)
            for ref in refs:
                if ref.startswith(('#', '/', '\\')) or '{' in ref or '<' in ref:
                    continue
                parsed = urlsplit(ref)
                if parsed.scheme or not parsed.path:
                    continue
                checked['relativeLinks'] += 1
                if not (p.parent/unquote(parsed.path)).exists():
                    issues.append({'kind': 'link', 'file': rel, 'target': ref})
        if suffix in SOURCE | {'.md', '.html', '.json', '.txt', '.manifest', '.svg'}:
            checked['textFilesScannedForStrongTokenPatterns'] += 1
            text = p.read_text(encoding='utf-8-sig')
            for label, pattern in tokens.items():
                for match in pattern.finditer(text):
                    secret_hits.append({'file': rel, 'line': text.count('\n', 0, match.start())+1, 'kind': label})
    dependencies = {}
    for package in ('Pillow', 'numpy', 'scipy', 'imageio-ffmpeg'):
        try:
            dependencies[package] = metadata.version(package)
        except metadata.PackageNotFoundError:
            dependencies[package] = None
    configurations = {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
                      for name in CONFIGURATIONS if (ROOT/name).exists()}
    report = {
        'generatedAtUtc': datetime.now(timezone.utc).isoformat(),
        'scope': 'git tracked plus nonignored untracked files; no runtime task data or credentials loaded',
        'headBeforeReviewCommit': git('rev-parse', 'HEAD'),
        'branch': git('branch', '--show-current'),
        'platform': {'system': platform.system(), 'release': platform.release(), 'python': platform.python_version(), 'packages': dependencies},
        'fileCount': len(paths), 'totalBytes': sum(sizes.values()),
        'physicalSourceLinesByExtension': dict(lines),
        'sourceFiles': len(hashes),
        'sourceFingerprint': hashlib.sha256(json.dumps({'code': hashes, 'configuration': configurations}, sort_keys=True).encode()).hexdigest(),
        'sourceHashes': hashes,
        'configurationHashes': configurations,
        'largestFiles': [{'file': f, 'bytes': n} for f, n in sorted(sizes.items(), key=lambda x: -x[1])[:15]],
        'rasterBytes': raster_bytes, 'checks': dict(checked), 'decodedRasterFirstFrames': args.decode_raster,
        'issues': issues, 'strongTokenPatternHits': secret_hits,
        'limitations': ['No external links requested', 'No formal coverage measurement', 'Raster scan alone does not verify every GIF frame', 'Token pattern scan is not an exhaustive security audit'],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('fileCount', 'totalBytes', 'sourceFiles', 'physicalSourceLinesByExtension', 'checks', 'issues', 'strongTokenPatternHits')}, ensure_ascii=False))
    return bool(issues or secret_hits)


if __name__ == '__main__':
    raise SystemExit(main())
