"""Export the approved imagegen icon to app PNG/ICO sizes without redrawing it."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/brand/v4"
source = OUT / "source.png"
sizes = (16, 20, 24, 32, 40, 48, 64, 128, 256, 512, 1024)
icons = OUT / "icons"
icons.mkdir(parents=True, exist_ok=True)
with Image.open(source) as raw:
    image = raw.convert("RGBA")
assert image.width == image.height, "Expected a square source."
assert image.getchannel("A").getextrema()[0] == 0, "Expected transparent background."
for size in sizes:
    image.resize((size, size), Image.Resampling.LANCZOS).save(icons / f"omnivibe-{size}.png")
image.save(icons / "omnivibe.ico", sizes=[(s, s) for s in sizes if s <= 256])
files = [source, *sorted(icons.glob("*"))]
(OUT / "manifest.json").write_text(json.dumps({
    "method": "Built-in imagegen; PNG/ICO format and size export only",
    "files": [{"path": p.relative_to(OUT).as_posix(), "bytes": p.stat().st_size,
               "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
}, indent=2), encoding="utf-8")
rows = "".join(f'<div><img src="icons/omnivibe-{s}.png" width="{s}" height="{s}"><span>{s}px</span></div>' for s in (16, 20, 24, 32, 48, 64, 128, 256))
(OUT / "index.html").write_text('''<!doctype html><meta charset="utf-8"><title>OmniVibe v3 icon</title>
<style>body{font:14px Segoe UI,sans-serif;margin:0;background:#eef1f4}header{padding:30px;font-size:24px}section{padding:28px;display:flex;align-items:center;gap:30px;flex-wrap:wrap}section.dark{background:#10141b;color:#eff4fa}section.light{background:#f5f7fa;color:#222}section div{display:flex;flex-direction:column;align-items:center;gap:18px}span{font-size:12px;opacity:.7}img{object-fit:contain}</style>
<header>OmniVibe · Pocket Hamster</header><section class="light">''' + rows + '</section><section class="dark">' + rows + '</section>', encoding="utf-8")
print(f"Exported {len(files)} icon files to {OUT}")
