"""Offline comparison of existing Terminal artwork and code-native frame geometry.

This is a deterministic design fixture, not a Windows Terminal screenshot or
GPU/DirectWrite benchmark. Original artwork and live settings are read-only.
"""
from __future__ import annotations

import hashlib
import html
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/terminal-frame-comparison"
FONT_ROOT = Path("C:/Windows/Fonts")
UI = str(FONT_ROOT / "msyh.ttc")
MONO = str(FONT_ROOT / "CascadiaMono.ttf")
VARIANTS = {"A": "保留内框", "B": "只留外框", "C": "内框整体外移"}
SIZES = {"regular": (1280, 800), "compact": (960, 600)}
PAD_X, PAD_Y, TITLE = 36, 32, 46


def color(value):
    return np.array([int(value[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def stroke(d, t=.45):
    return 1 - smooth(t, t + .65, np.abs(d))


def fract(x):
    return x - np.floor(x)


def masks(slug, width, height, bounds, time=8.0):
    """Numpy port of shaders/designs/*.hlsl (shape masks only).

    Frame coordinates are translated/expanded for C, not scaled down. Thus
    corner ornament sizes remain constant and the original viewport is enclosed.
    """
    yy, xx = np.mgrid[:height, :width].astype(np.float32)
    l, t, r, b = bounds
    px, py = xx - l, yy - t
    sx, sy = r - l, b - t
    qx, qy = np.minimum(px, sx - px), np.minimum(py, sy - py)
    edge = np.minimum(qx, qy)
    corner = 1 - smooth(30, 40, np.maximum(qx, qy))
    slow = .70 + .12 * math.sin(time * .4)
    inside = (edge >= 0) & (edge <= 24)

    def seg(a, b):
        vx, vy = b[0] - a[0], b[1] - a[1]
        f = np.clip(((qx - a[0]) * vx + (qy - a[1]) * vy) / max(vx * vx + vy * vy, .001), 0, 1)
        return stroke(np.hypot(qx - a[0] - f * vx, qy - a[1] - f * vy))

    def ring(cx, cy, radius):
        return stroke(np.hypot(qx - cx, qy - cy) - radius)

    def diamond(cx, cy, radius):
        return stroke(np.abs(qx - cx) + np.abs(qy - cy) - radius)

    mx = np.maximum
    if slug == "hextech":
        gx, gy = qx - 17, qy - 17
        angle = np.arctan2(gy, gx) + time * .035
        tooth = 10.5 + 1.35 * smooth(-.15, .15, np.cos(angle * 12))
        ink = mx(stroke(np.hypot(gx, gy) - tooth, .65) * corner, ring(17, 17, 6.5) * corner)
        ink = mx(ink, stroke(edge - 7, .3) * .38)
        light = mx(diamond(17, 17, 3.5) * corner * slow,
                   stroke(edge - 11.5, .2) * (.24 + .13 * np.sin((px + py) * .035 - time * .45)))
    elif slug == "tactical":
        ticks = 1 - smooth(.6, 1.3, np.abs(fract((px + py) / 24) - .5) * 24)
        ink = mx(stroke(edge - 8, .35) * .60, ticks * (edge >= 9) * (edge < 14) * .65)
        ink = mx(ink, mx(seg((7,28),(7,7)), seg((7,7),(28,7))) * corner)
        scanner = 1 - smooth(0, 46, np.abs(py - fract(time / 24) * sy))
        light = mx(scanner * stroke(qx - 17, .65) * .65, seg((16,23),(23,16)) * corner * slow)
    elif slug == "protocol":
        ink = mx(seg((7,29),(7,17)), seg((7,17),(17,7)))
        ink = mx(ink, seg((17,7),(29,7))) * corner
        ink = mx(ink, stroke(edge - 7, .35) * (np.maximum(qx, qy) >= 37) * .30)
        dashed = fract((px + py - time * 5) / 44) >= .72
        light = mx(dashed * stroke(edge - 11, .7) * .65, seg((15,26),(26,15)) * corner * slow)
    elif slug == "adventure":
        ink = mx(mx(stroke(edge - 6, .9), stroke(edge - 11, .4) * .55), ring(18,18,3.4) * corner)
        bevel = mx(seg((7,28),(28,7)), seg((12,28),(28,12))) * corner
        light = mx(bevel * .65, ring(18,18,.8) * corner * slow)
        light = mx(light, stroke(edge - 8, .2) * (.12 + .08 * np.sin(px * .018 + py * .012 - time * .3)))
    elif slug == "arsenal":
        ink = mx(seg((6,30),(27,9)), seg((9,27),(30,6))) * corner
        ink = mx(mx(ink, diamond(18,18,8) * corner * .70), stroke(edge - 7.5, .45) * .34)
        light = mx(seg((14,23),(23,14)), seg((15,14),(22,21))) * corner * slow
        rune = stroke(np.abs(fract(px / 100) * 100 - 50) + np.abs(qy - 13) - 3)
        light = mx(light, rune * (qy < 24) * .45)
    elif slug == "relic":
        ink = mx(seg((6,31),(6,6)), seg((6,6),(31,6))) * corner
        ink = mx(ink, mx(seg((12,30),(12,18)), seg((12,18),(18,12))) * corner)
        ink = mx(mx(ink, seg((18,12),(30,12)) * corner), stroke(edge - 6, .6) * .25)
        light = mx(mx(ring(20,20,4.2), seg((20,14),(20,26))) * corner * slow, stroke(edge - 9, .2) * .16)
    elif slug == "starlight":
        gx, gy = qx - 18, qy - 18
        ink = mx(mx(ring(18,18,11), ring(18,18,8.2) * .4) * corner, stroke(edge - 7, .3) * .35)
        rays = np.minimum(np.abs(gx), np.abs(gy))
        light = (1 - smooth(0, 1, rays)) * (1 - smooth(0, 7, np.hypot(gx, gy))) * corner * slow
        light = mx(mx(light, diamond(18,18,4.5) * corner * .65), stroke(edge - 11, .2) * .16)
    elif slug == "formation":
        tx, ty = np.maximum(np.abs(qx - 17) - 7, 0), np.maximum(np.abs(qy - 17) - 7, 0)
        ink = mx(stroke(np.hypot(tx,ty) - 3) * corner, stroke(edge - 7, .3) * .35)
        bays = (fract(px / 32) >= .56) * (qy >= 11) * (qy < 15)
        ink = mx(ink, bays * .30)
        light = ring(17,17,3) * corner * slow
        ux, uy = 17 + math.cos(time * .15) * 8, 17 + math.sin(time * .15) * 8
        light = mx(light, (1 - smooth(.4,1.7,np.hypot(qx - ux,qy - uy))) * corner * .60)
    elif slug == "astral":
        ink = mx(seg((7,29),(14,14)), seg((14,14),(29,7))) * corner
        ink = mx(mx(ink, seg((14,14),(25,25)) * corner * .70), stroke(edge - 7, .16) * .26)
        light = mx(ring(14,14,2), ring(25,25,1.1)) * corner * slow
        light = mx(light, diamond(29,7,2.4) * corner * .55)
        node = stroke(np.hypot(fract(px / 143) * 143 - 71.5, qy - 8.5) - 1.6)
        light = mx(light, node * (qy < 24) * .35)
    elif slug == "wonderland":
        cloud = mx(mx(ring(13,19,6), ring(20,14,5)), ring(26,20,4))
        ink = mx(cloud * corner, stroke(edge - 7, .6) * .45)
        wave = 11.5 + 1.2 * np.sin(px * .028 - time * .20)
        light = mx(stroke(qy - wave, .4) * (qy < 24) * .42, diamond(19,22,2.6) * corner * slow)
    elif slug == "ink-jade":
        # Legacy Ink Jade geometry, same coordinates as ornate-frame-v2.hlsl.
        inside = (edge >= 0) & (edge <= 33)
        frame = mx(stroke(edge - 6.5, .35), stroke(edge - 10.5, .2) * .42)
        ink = frame * .72
        ornament = np.zeros_like(edge)
        for a, b in [((7,30),(7,7)),((7,7),(30,7)),((12,30),(12,12)),((12,12),(30,12)),
                     ((19,30),(29,30)),((29,30),(29,19)),((29,19),(23,19)),((23,19),(23,24))]:
            ornament = mx(ornament,seg(a,b))
        ornament = mx(ornament,ring(17,17,5.5)) * (np.maximum(qx,qy) < 33)
        ink = mx(ink, ornament * .92)
        light = (1 - smooth(2.5,4.4,np.abs(qx - 17) + np.abs(qy - 17))) * (np.maximum(qx,qy) < 33) * slow
    else:
        raise ValueError(slug)
    return ink * inside * .66, light * inside * .78


def mix(image, target, alpha):
    return image * (1 - alpha[:, :, None]) + target * alpha[:, :, None]


def base_art(row, width, height):
    art = Image.open(ROOT / row["artwork"]).convert("RGB")
    art = art.resize((width, height), Image.Resampling.LANCZOS) if row["slug"] == "ink-jade" else ImageOps.fit(art, (width,height), method=Image.Resampling.LANCZOS)
    raw = np.asarray(art).astype(np.float32)
    yy, xx = np.mgrid[:height, :width]
    edge = np.minimum(np.minimum(xx,width - 1 - xx),np.minimum(yy,height - 1 - yy))
    opacity = row["imageOpacity"]
    # Common backdrop for all three schemes, so border position is the variable.
    # The rim boost mirrors the skins' intent without post-processing glyphs.
    alpha = opacity * (1 + 2.25 * (1 - smooth(5,24,edge))) if opacity < .2 else np.full_like(edge,opacity,dtype=float)
    return mix(np.broadcast_to(color(row["background"]),raw.shape).copy(), raw, alpha)


def glyphs(row, width, height):
    layer = Image.new("RGBA", (width,height))
    d = ImageDraw.Draw(layer)
    mono = ImageFont.truetype(MONO,20)
    cjk = ImageFont.truetype(UI,20)
    symbol = ImageFont.truetype(str(FONT_ROOT / "seguisym.ttf"),20)
    baseline_offset = max(face.getmetrics()[0] for face in (mono, cjk, symbol))
    cell = mono.getlength("M")
    columns = int((width - 2 * PAD_X) / cell)
    rows = int((height - 2 * PAD_Y) / 28)
    fixture = [
        ("$ codex resume --last", "text"),
        ("› 优化窗口状态检测与任务恢复逻辑", "text"),
        ("", "muted"),
        ("• 已读取 Manager.cs，正在检查窗口置前顺序。", "text"),
        ("  工作目录 D:\\tools\\OmniVibe", "muted"),
        ("$ git diff --stat", "secondary"),
        (" src/CodeManager/Manager.cs | 28 +++++++++++++-------", "text"),
        (" 1 file changed, 18 insertions(+), 10 deletions(-)", "muted"),
        ("", "text"),
        ("• Running validation (00:18)", "accent"),
        ("  ✓ 配置与窗口绑定保持不变", "running"),
        ("  ✓ restore → Alt+1 → foreground", "running"),
        ("  ! 等待确认：Allow this command? [y/n]", "waiting"),
        ("", "text"),
        ("  112  if (window.IsMinimized)", "text"),
        ("  113      Restore(window.Handle);", "text"),
        ("+ 114  Activate(window.Handle);", "running"),
    ]
    # Keep both first and last glyph rows at the same coordinates in A/B/C.
    fixture = fixture[:max(rows - 3, 1)]
    while len(fixture) < rows - 2:
        fixture.append(("", "text"))
    fixture += [("› 继续修复并检查当前任务…", "text"), ("GPT-6.1 · D:\\tools\\OmniVibe · Main [default]", "muted")]
    for line_no, (text, key) in enumerate(fixture):
        x, y, used = PAD_X, PAD_Y + line_no * 28, 0
        for char in text:
            wide = ord(char) > 0x2ff
            units = 2 if wide else 1
            if used + units > columns:
                break
            face = symbol if char == "✓" else (cjk if wide else mono)
            # Keep letters, punctuation and fallback glyphs on one baseline.
            # Per-character top anchoring raises short glyphs and makes normal
            # code look distorted even though the image decodes correctly.
            d.text((x,y + baseline_offset),char,font=face,fill=row[key],anchor="ls")
            x += cell * units
            used += units
    rgba = np.asarray(layer)
    return rgba[:,:,:3].astype(np.float32), rgba[:,:,3].astype(np.float32) / 255


def outer_rim(row, width, height):
    yy, xx = np.mgrid[:height,:width].astype(np.float32)
    # The legacy illustration already has a complete physical border. The ten
    # game illustrations get one quiet outer hairline instead of a second box.
    if row["slug"] == "ink-jade":
        l,r,t,b=width*.007,width*.993,height*.012,height*.961
        static = np.zeros_like(xx)
    else:
        l,r,t,b=7,width-8,7,height-8
        q=np.minimum(np.minimum(np.abs(xx-l),np.abs(xx-r)),np.minimum(np.abs(yy-t),np.abs(yy-b)))
        static=stroke(q,.28)*.38
    dx=np.minimum(np.abs(xx-l),np.abs(xx-r))
    dy=np.minimum(np.abs(yy-t),np.abs(yy-b))
    dist=np.minimum(dx,dy)
    band=(dist<=5)&(xx>=l-5)&(xx<=r+5)&(yy>=t-5)&(yy<=b+5)
    horizontal,vertical=r-l,b-t
    perimeter=2*(horizontal+vertical)
    along=np.where(dx<dy,np.where(xx>(l+r)/2,horizontal+yy-t,perimeter-(yy-t)),
                   np.where(yy>(t+b)/2,horizontal+vertical+r-xx,xx-l))
    signed=(along-perimeter*.18+perimeter/2)%perimeter-perimeter/2
    pulse=np.exp(-(signed/125)**2)*np.exp(-(dist/1.5)**2)*band*.86
    valid=(xx>=l-2)&(xx<=r+2)&(yy>=t-2)&(yy<=b+2)
    return static*valid,pulse


def chrome(body, row, width, height):
    im=Image.new("RGB",(width,height),row["background"])
    im.paste(Image.fromarray(np.clip(np.rint(body),0,255).astype(np.uint8)),(0,TITLE))
    d=ImageDraw.Draw(im); f=ImageFont.truetype(UI,14)
    d.rounded_rectangle((9,7,326,39),radius=5,fill=row["surface"])
    d.text((24,13),"OV  OmniVibe · 边框对比 / 示例任务",font=f,fill=row["text"])
    d.text((345,12),"+",font=ImageFont.truetype(UI,19),fill=row["muted"])
    d.text((width-112,13),"─     □     ×",font=f,fill=row["muted"])
    return im


def render(row, mode):
    width, height=SIZES[mode]; bh=height-TITLE
    backdrop=base_art(row,width,bh)
    foreground,alpha=glyphs(row,width,bh)
    with_text=mix(backdrop,foreground,alpha)
    original=(PAD_X,PAD_Y,width-PAD_X,bh-PAD_Y)
    expanded=(2,2,width-2,bh-2)
    assert expanded[0] < original[0] and expanded[1] < original[1]
    assert expanded[2] > original[2] and expanded[3] > original[3]
    images={};metrics={}
    for variant in VARIANTS:
        if variant=="B":
            ink,light=outer_rim(row,width,bh)
        else:
            ink,light=masks(row["slug"],width,bh,original if variant=="A" else expanded)
        effect=np.maximum(ink,light)
        overlap=int(np.count_nonzero((effect>.025)&(alpha>.15)))
        if variant in ("B","C") and overlap:
            raise AssertionError(f"{row['slug']} {mode} {variant} touches foreground glyphs")
        # A matches the old post-text placement. B/C render below the glyphs.
        frame_base=with_text if variant=="A" else backdrop
        framed=mix(mix(frame_base,color(row.get("frameSecondary",row["secondary"])),ink),color(row.get("frameAccent",row["accent"])),light)
        body=framed if variant=="A" else mix(framed,foreground,alpha)
        name=f"{row['slug']}-{variant}-{mode}.png"
        result=chrome(body,row,width,height)
        result.save(OUT/name,optimize=True)
        images[variant]=result
        if variant == "B":
            measured_bounds = ((width*.007,bh*.012,width*.993,bh*.961)
                               if row["slug"] == "ink-jade" else (7,7,width-8,bh-8))
        else:
            measured_bounds = original if variant == "A" else expanded
        metrics[variant]={"image":name,"glyphEffectIntersectionPixels":overlap,
                          "frameBounds":[round(x,2) for x in measured_bounds],
                          "foregroundPreserved":variant!="A",
                          "originalViewportEnclosed":variant=="C"}
    return images,metrics


def triptych(row,images):
    tile_w=680; gap=20; left=24; top=110; crop_y=top+425+46
    canvas=Image.new("RGB",(left*2+tile_w*3+gap*2,crop_y+180+42),"#101923")
    d=ImageDraw.Draw(canvas)
    d.text((24,16),row["name"]+"  /  三种边框布局",font=ImageFont.truetype(UI,30),fill="#F3EFE4")
    d.text((24,61),"同一插画、文字、字号与留白 · 离线合成预览，非 Terminal 实机截图 · 下方为左上角原尺寸细节",font=ImageFont.truetype(UI,17),fill="#A9BDCB")
    for n,(variant,label) in enumerate(VARIANTS.items()):
        x=left+n*(tile_w+gap)
        im=images[variant]
        d.text((x,top-27),f"{variant}  {label}",font=ImageFont.truetype(UI,20),fill="#B8DCCF" if variant=="C" else "#E1DDCF")
        canvas.paste(im.resize((tile_w,425),Image.Resampling.LANCZOS),(x,top))
        crop=im.crop((0,TITLE,680,TITLE+180))
        canvas.paste(crop,(x,crop_y))
        d.text((x,crop_y-26),"左上角 · 100% 原尺寸",font=ImageFont.truetype(UI,16),fill="#A9BDCB")
    name=row["slug"]+"-compare.png";canvas.save(OUT/name,optimize=True)
    return name


def geometry_diagram():
    im=Image.new("RGB",(1500,510),"#101923");d=ImageDraw.Draw(im)
    title=ImageFont.truetype(UI,25);small=ImageFont.truetype(UI,18)
    for i,v in enumerate(VARIANTS):
        x=24+i*500
        d.text((x,18),v+"  "+VARIANTS[v],font=title,fill="#EEE9DC")
        d.rectangle((x,80,x+450,360),outline="#8C9AAA",width=2)
        old=(x+42,118,x+408,322)
        d.rectangle(old,fill="#1E3341",outline="#78B9E6",width=2)
        if v=="A": d.rectangle((x+49,125,x+401,315),outline="#F5CB82",width=3)
        elif v=="B": d.rectangle((x+7,87,x+443,353),outline="#F5CB82",width=2)
        else:
            d.rectangle((x+7,87,x+443,353),outline="#F5CB82",width=3)
            for cx,cy in [(x+12,92),(x+420,92),(x+12,330),(x+420,330)]:
                d.line((cx,cy+16,cx,cy,cx+16,cy),fill="#F5CB82",width=3)
        d.text((x+90,205),"原有文字区域 · 保持不变",font=small,fill="#DDE8F2")
        text={"A":"装饰进入文字区，可能与字形重叠", "B":"只用外缘细线 / 插画自带外框", "C":"角纹留在外缘留白，框线完整包住原区域"}[v]
        d.text((x,390),text,font=small,fill="#AFC3D0")
    d.text((24,457),"几何示意，非精确比例：蓝色 = 原有文字区域；金色 = 边框 / 装饰。C 扩大的是边框，不缩小文字区域。",font=small,fill="#AFC3D0")
    im.save(OUT/"geometry.png",optimize=True)


def page(rows,report):
    data=[{"slug":r["slug"],"name":r["name"],"subtitle":r["subtitle"]} for r in rows]
    articles=[]
    for i,r in enumerate(rows):
        slug=r["slug"]; name=html.escape(r["name"])
        cards=[]
        for v,label in VARIANTS.items():
            cards.append(f'<button class="shot" data-slug="{slug}" data-v="{v}" aria-label="放大{name} {v} {label}"><span>{v} · {label}</span><img loading="lazy" width="1280" height="800" src="{slug}-{v}-regular.png" alt="{name} {label}"></button>')
        articles.append(f'<article id="{slug}"><div class="rowhead"><h2>{i+1:02d} · {name}</h2><p>{html.escape(r["subtitle"])}</p><a href="{slug}-compare.png">下载三联对比图（含角部原尺寸细节）↗</a></div><div class="columns">'+''.join(cards)+'</div></article>')
    document='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OmniVibe · 十套主题的三种边框对比</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#0c131c;color:#eeeade;font:15px/1.7 system-ui,"Microsoft YaHei UI",sans-serif}main{max-width:2200px;margin:auto;padding:32px}h1{font-size:36px;line-height:1.25;margin:10px 0 16px}header{max-width:1080px}p{color:#aebdcb}a{color:#b4dbd1}button,select{font:inherit;color:inherit;background:#172532;border:1px solid #3f5365;border-radius:7px;padding:8px 14px;cursor:pointer}button:hover,a:hover{color:#fff;border-color:#b4dbd1}.recommend{border-left:3px solid #a6cfb8;padding:12px 20px;background:#15251f;margin:22px 0}.toolbar{position:sticky;top:0;z-index:2;background:#0c131cf5;border-block:1px solid #2d3f4e;display:flex;gap:12px;align-items:center;padding:14px 0;flex-wrap:wrap}.toolbar p{margin:0}.columns{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}.rowhead{display:flex;align-items:baseline;gap:20px;flex-wrap:wrap;margin-top:40px}.rowhead h2{margin:0;font-size:25px}.rowhead p{margin:0}.rowhead a{margin-left:auto;font-size:13px}.shot{text-align:left;padding:0;border-radius:9px;overflow:hidden;background:#14202c}.shot span{display:block;padding:10px 14px;background:#1a2937;font-weight:600}.shot[data-v=C] span{color:#b4dbd1}.shot img{display:block;width:100%;height:auto}.diagram{max-width:1200px;width:100%;margin:20px 0}.note{font-size:13px}.links{display:flex;gap:20px;flex-wrap:wrap}.hide{display:none}dialog{width:96vw;max-width:none;height:96vh;background:#0b131c;color:#eeeade;border:1px solid #526777;padding:18px;border-radius:12px}dialog::backdrop{background:#000c}.modalbar{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.modalbar h2{margin:0 auto 0 0;font-size:20px}.modalbar button[aria-pressed=true]{background:#31584c;border-color:#a6cfb8}.viewer{overflow:auto;height:calc(100% - 80px);margin-top:14px;display:flex;align-items:flex-start;justify-content:center}.viewer img{max-width:100%;height:auto}.viewer.actual{display:block}.viewer.actual img{max-width:none}body:has(dialog[open]){overflow:hidden}@media(max-width:800px){main{padding:18px}.columns{grid-template-columns:1fr}.rowhead a{margin-left:0}h1{font-size:28px}.toolbar{position:relative}.rowhead{gap:6px}dialog{height:98vh;width:99vw}.modalbar h2{width:100%}}
</style><main><header><p>OmniVibe / Terminal 设计评审</p><h1>同一段终端内容，三种边框取舍。</h1><p>十套游戏主题全部对比，另附当前墨玉参考。A 保留内框；B 只留安静的外框；C 把各主题的边框与角饰整体外移，完整包住原文字区域。字号、文字起点和可用区域保持相同。</p><p class="note">离线设计合成：使用仓库原插画、配色与 HLSL 边框几何；不是 Windows Terminal 实机截图。光效定格于同一时刻，不能用来判断真实播放帧率。预览不会修改当前 Terminal。</p>
<div class="recommend"><strong>已选定 C：十套主题与墨玉都采用边框整体外移；B 保留为专注方向。</strong><br>C 保留各主题角饰，并完整包住原文字区域。墨玉也按 C 细化，将角饰与原外框融合成一套边饰。A 仍有字形相交，不继续采用。十套 C 方案的质量细化见<a href="../terminal-frame-refinement/index.html">新版前后对比</a>。</div>
<div class="links"><a href="overview-01.png">总览图 1 / 五套主题</a><a href="overview-02.png">总览图 2 / 五套主题</a><a href="geometry.png">三种布局的区域示意</a><a href="review.md">评审与验证说明</a></div></header>
<details><summary>第三种方案具体往哪里移？</summary><img class="diagram" src="geometry.png" alt="A 内框进入文字区；B 单外框；C 外移后包住原区域的示意"></details>
<div class="toolbar"><label>窗口尺寸 <select id="size"><option value="regular">1280 × 800 常规窗口</option><option value="compact">960 × 600 窄窗口</option></select></label><label>主题 <select id="theme"><option value="all">全部十套 + 墨玉参考</option></select></label><p>点击任一预览放大；放大后用 1 / 2 / 3 切换 A / B / C，方向键切主题，Esc 关闭。</p></div>
'''+''.join(articles)+'''
<dialog id="modal"><div class="modalbar"><h2 id="modalTitle"></h2><button data-modal-v="A">1 · 内框</button><button data-modal-v="B">2 · 外框</button><button data-modal-v="C">3 · 外移</button><button id="zoom">100% 原尺寸</button><button id="close">关闭 ×</button></div><div class="viewer" id="viewer"><img id="large" alt=""></div></dialog>
<script>
const rows=__DATA__;
const size=document.getElementById('size'),theme=document.getElementById('theme'),modal=document.getElementById('modal'),large=document.getElementById('large'),viewer=document.getElementById('viewer');
let active=0,variant='C';
rows.forEach(r=>theme.add(new Option(r.name,r.slug)));
function refreshLarge(){const r=rows[active];large.src=`${r.slug}-${variant}-${size.value}.png`;large.alt=r.name+' '+variant;document.getElementById('modalTitle').textContent=r.name+' · '+variant+' · '+(size.value==='regular'?'1280 × 800':'960 × 600');document.querySelectorAll('[data-modal-v]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.modalV===variant)));}
size.addEventListener('change',()=>{document.querySelectorAll('.shot').forEach(b=>b.querySelector('img').src=`${b.dataset.slug}-${b.dataset.v}-${size.value}.png`);refreshLarge();});
theme.addEventListener('change',()=>document.querySelectorAll('article').forEach(a=>a.classList.toggle('hide',theme.value!=='all'&&a.id!==theme.value)));
document.querySelectorAll('.shot').forEach(b=>b.addEventListener('click',()=>{active=rows.findIndex(r=>r.slug===b.dataset.slug);variant=b.dataset.v;refreshLarge();modal.showModal();}));
document.querySelectorAll('[data-modal-v]').forEach(b=>b.addEventListener('click',()=>{variant=b.dataset.modalV;refreshLarge();}));
document.getElementById('close').onclick=()=>modal.close();document.getElementById('zoom').onclick=e=>{viewer.classList.toggle('actual');e.target.textContent=viewer.classList.contains('actual')?'适应窗口':'100% 原尺寸';};
document.addEventListener('keydown',e=>{if(!modal.open)return;if('123'.includes(e.key)){variant='ABC'[Number(e.key)-1];refreshLarge();}if(e.key==='ArrowLeft'||e.key==='ArrowRight'){active=(active+(e.key==='ArrowRight'?1:-1)+rows.length)%rows.length;refreshLarge();e.preventDefault();}});
</script></main></html>'''
    document=document.replace('__DATA__',json.dumps(data,ensure_ascii=False))
    (OUT/"index.html").write_text(document,encoding="utf-8")


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/"skins/catalog.json").read_text(encoding="utf-8"))
    manifest=json.loads((ROOT/"themes/windows-terminal/skins.json").read_text(encoding="utf-8"))
    by_slug={r["slug"]:r for r in manifest["skins"]}
    rows=[dict(r,imageOpacity=by_slug[r["slug"]]["imageOpacity"]) for r in catalog]
    jade=json.loads((ROOT/"themes/windows-terminal/OmniVibe-InkJade.json").read_text(encoding="utf-8"))
    rows.append(dict(slug="ink-jade",name="墨玉 · 当前主题参考",subtitle="完整插画外框 · 作为额外参考，不计入十套",
                     artwork="themes/windows-terminal/assets/ink-jade-ornate-v2.png",background=jade["background"],surface="#1C3027",
                     text=jade["foreground"],muted=jade["brightBlack"],accent=jade["cursorColor"],secondary=jade["cyan"],
                     running=jade["green"],waiting=jade["yellow"],imageOpacity=.5,frameSecondary="#AD874F",frameAccent="#94D1AB"))
    source_hashes={r["slug"]:hashlib.sha256((ROOT/r["artwork"]).read_bytes()).hexdigest() for r in rows}
    report={"kind":"offline deterministic design fixtures; not Terminal screenshots", "themes":[], "gameThemes":10,
            "bonusReferenceThemes":1,"variants":VARIANTS,"sizes":SIZES,"terminalSettingsChanged":False,
            "frameGeometrySource":"themes/windows-terminal/shaders/designs/*.hlsl", "actualGpuRendering":False,
            "timeSeconds":8.0,
            "comparisonScope":"frame placement and glyph interference; not an exact Terminal compositing simulation",
            "backgroundAndTextIdenticalAcrossVariants":True,"liveTerminalThemeChanged":False}
    triptychs=[]
    for row in rows:
        theme_report={"slug":row["slug"],"name":row["name"],"artwork":row["artwork"],"sourceSha256":source_hashes[row["slug"]],"sizes":{}}
        for mode in SIZES:
            images,metrics=render(row,mode)
            theme_report["sizes"][mode]=metrics
            if mode=="regular":
                triptychs.append(triptych(row,images))
        if hashlib.sha256((ROOT/row["artwork"]).read_bytes()).hexdigest()!=source_hashes[row["slug"]]:
            raise AssertionError("Source artwork changed")
        report["themes"].append(theme_report)
        print(row["slug"],theme_report["sizes"]["regular"]["A"]["glyphEffectIntersectionPixels"],flush=True)
    geometry_diagram()
    for part in range(2):
        thumbs=[]
        for name in triptychs[part*5:part*5+5]:
            im=Image.open(OUT/name);im.thumbnail((2100,800),Image.Resampling.LANCZOS);thumbs.append(im.copy())
        canvas=Image.new("RGB",(2100,sum(im.height for im in thumbs)+20*len(thumbs)),"#101923")
        y=0
        for im in thumbs:canvas.paste(im,(0,y));y+=im.height+20
        canvas.save(OUT/f"overview-{part+1:02d}.png",optimize=True)
    report["allMovedFramesEncloseOriginalViewport"]=all(t["sizes"][m]["C"]["originalViewportEnclosed"] for t in report["themes"] for m in SIZES)
    report["allBAndCGlyphIntersectionsZero"]=all(t["sizes"][m][v]["glyphEffectIntersectionPixels"]==0 for t in report["themes"] for m in SIZES for v in ("B","C"))
    report["fixtureCount"]=len(rows)*len(SIZES)*3
    report["allSourcesUnmodified"]=True
    (OUT/"validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    page(rows,report)
    print(f"Generated {len(rows)} themes, {report['fixtureCount']} fixtures, 11 triptychs and 2 overview sheets.")


if __name__=="__main__":main()
