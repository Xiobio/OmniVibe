"""Arrange actual native QA screenshots; never edits the original illustrations.

Run from the repository root after CodeManager --preview has produced
artifacts/skin-previews/<slug>/{inventory,compact,settings-skin,menu}.png.
Requires Pillow. Source is UTF-8 to preserve Chinese captions on Windows.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import html
import json

rows = json.loads(Path("skins/catalog.json").read_text(encoding="utf-8"))
root = Path("docs/skin-gallery")
root.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 32)
small = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
index = []
markdown = ["# OmniVibe 十套皮肤图册", "", "实际原生界面截图，点击图片放大。包含总览、侧栏、皮肤设置和右键菜单；使用示例任务，不包含真实终端内容。", "", "[HTML 图册](index.html) · [检验与校准](../../skins/VALIDATION.md)", ""]
for number, row in enumerate(rows, 1):
    canvas = Image.new("RGB", (1600, 1800), "#111B22")
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 18), f"{number:02d}  {row['name']}", font=font, fill="#EEE7D5")
    draw.text((24, 65), row["subtitle"] + "  ·  OmniVibe 原生界面截图", font=small, fill="#B6C8CD")
    for mode, position, bounds, label in [
        ("inventory", (24, 120), (1280, 960), "任务总览 / 6 个任务 + 3 个空槽"),
        ("compact", (1324, 120), (250, 650), "右侧任务栏"),
        ("settings-skin", (24, 1130), (780, 653), "设置 / 当前皮肤与配套 Terminal 入口"),
        ("menu", (880, 1130), (310, 490), "右键菜单"),
    ]:
        draw.text((position[0], position[1] - 28), label, font=small, fill="#B6C8CD")
        source = Path("artifacts/skin-previews") / row["slug"] / (mode + ".png")
        picture = Image.open(source).convert("RGB")
        picture.thumbnail(bounds, Image.Resampling.LANCZOS)
        canvas.paste(picture, position)
    folder = root / row["slug"]
    folder.mkdir(exist_ok=True)
    canvas.save(folder / "preview.png", optimize=True)
    name = html.escape(row["name"])
    subtitle = html.escape(row["subtitle"])
    slug = row["slug"]
    index.append(f'<article><h2>{name}</h2><p>{subtitle}</p><a href="{slug}/preview.png"><img loading="lazy" src="{slug}/preview.png" alt="{name}：任务栏、总览、设置与右键菜单截图"></a></article>')
    markdown.extend([f"## {row['name']}", "", row["subtitle"], "", f"[![{row['name']} 原生皮肤套装截图]({slug}/preview.png)]({slug}/preview.png)", ""])

page = """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OmniVibe · 十套皮肤图册</title>
<style>body{margin:0;background:#10191f;color:#eee8db;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1500px;margin:auto;padding:36px 24px}h1{font-size:32px;margin:0}header{max-width:900px;margin-bottom:30px}p{color:#b9c8cd}a{color:#b9ddd9}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:28px}article{min-width:0;background:#18252d;border:1px solid #354851;padding:18px;border-radius:12px}h2{margin:0}article p{margin:4px 0 14px}img{display:block;width:100%;height:auto;border-radius:5px}@media(max-width:500px){section{grid-template-columns:1fr}main{padding:20px 12px}}</style>
<main><header><h1>OmniVibe · 十套皮肤图册</h1><p>每套展示实际 WPF 原生界面的任务总览、常驻任务栏、皮肤设置和右键菜单。点击截图可放大。示例包含五种执行状态、断开连接、未读与选中，以及三个空槽；无真实任务内容。</p><p><a href="../../skins/VALIDATION.md">检验与校准记录</a> · <a href="../skin-design-candidates.md">设计候选</a> · 配套 Terminal 插画与特效见仓库 themes/windows-terminal。</p></header><section>""" + "".join(index) + "</section></main></html>\n"
(root / "index.html").write_text(page, encoding="utf-8")
(root / "README.md").write_text("\n".join(markdown), encoding="utf-8")
print(f"Generated {len(rows)} suite screenshots and UTF-8 HTML/Markdown gallery")
