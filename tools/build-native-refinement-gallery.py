"""Publish actual WPF comparison renders; original artwork remains untouched."""
from pathlib import Path
import html
import json
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/native-skin-refinement'

def main():
    rows=json.loads((ROOT/'skins/native-v2/validation.json').read_text(encoding='utf-8'))['themes']
    rows=sorted(rows,key=lambda r: (0 if r['slug']=='ink-jade' else 2 if r['slug'] in ('midnight','cinnabar') else 1,))
    screens=OUT/'screens';screens.mkdir(parents=True,exist_ok=True)
    for version,modes in [('before',('expanded','inventory','mini')),('after',('expanded','inventory','mini','inventory-small','inventory-hidpi'))]:
        for row in rows:
            for mode in modes:
                source=ROOT/f"artifacts/native-polish/{version}/{row['slug']}-{mode}.png"
                with Image.open(source) as im:im.load()
                shutil.copy2(source,screens/f"{row['slug']}-{version}-{mode}.png")
    sheet=Image.new('RGB',(1120,208*4),'#101923');draw=ImageDraw.Draw(sheet)
    title=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15);small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',11)
    for i,row in enumerate(rows):
        x=i%4*280;y=i//4*208;parts=row['name'].split(' · ',1)
        draw.text((x+8,y+3),parts[0],font=title,fill='#F2EADC')
        draw.text((x+8,y+27),parts[1] if len(parts)>1 else '经典主题',font=small,fill='#AEBFC9')
        pics=[Image.open(screens/f"{row['slug']}-{v}-mini.png").convert('RGBA') for v in ('before','after')]
        boxes=[p.getbbox() for p in pics];box=(min(b[0] for b in boxes)-6,min(b[1] for b in boxes)-6,max(b[2] for b in boxes)+6,max(b[3] for b in boxes)+6)
        for n,pic in enumerate(pics):
            draw.text((x+8+n*136,y+49),'修改前' if n==0 else '修改后',font=small,fill='#99B9AE' if n else '#8B9BA7')
            crop=pic.crop(box);crop.thumbnail((126,130),Image.Resampling.LANCZOS)
            sheet.paste(crop,(x+8+n*136,y+71),crop)
    sheet.save(OUT/'core-before-after.png',optimize=True)
    cards=[]
    for row in rows:
        slug=row['slug'];name=html.escape(row['name'])
        cards.append(f'<article id="{slug}" data-slug="{slug}"><h2>{name}</h2><div class="pair">'+''.join(f'<figure><figcaption>{label}</figcaption><a class="zoom" href="screens/{slug}-{version}-expanded.png"><img loading="lazy" src="screens/{slug}-{version}-expanded.png" data-version="{version}" alt="{name} · {label}"></a></figure>' for version,label in [('before','修改前'),('after','修改后')])+f'</div><p class="links"><a href="screens/{slug}-after-inventory-small.png">小窗口布局</a><a href="screens/{slug}-after-inventory-hidpi.png">200% 缩放布局</a></p></article>')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OmniVibe · 原生组件细化</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#0c151d;color:#ede8dc;font:15px/1.7 system-ui,"Microsoft YaHei UI",sans-serif}main{max-width:1680px;padding:32px 26px;margin:auto}h1{font-size:36px;margin:10px 0}header{max-width:1060px}p{color:#afc1cb}a{color:#a5d9cb}nav,.links{display:flex;gap:18px;flex-wrap:wrap}aside{border-left:3px solid #b4d1c0;padding:12px 18px;background:#14231f;margin:24px 0}.toolbar{position:sticky;top:0;padding:12px 0;background:#0c151df5;display:flex;gap:8px;flex-wrap:wrap;border-bottom:1px solid #34454f;z-index:2}button{font:inherit;cursor:pointer;padding:8px 16px;border:1px solid #40545e;border-radius:7px;color:#dfe9e4;background:#162630}button[aria-pressed=true]{border-color:#a3d4bd;background:#294639}article{border-top:1px solid #34454f;margin-top:32px;padding-top:18px}h2{font-size:23px;margin:0 0 14px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px}figure{margin:0}figcaption{color:#b1c5ce;margin:0 0 8px}img{display:block;max-width:100%;height:auto;margin:auto}.zoom{display:flex;align-items:flex-start;justify-content:center;background:#101e29;border-radius:8px;overflow:hidden;min-height:160px}.zoom img{width:auto;max-height:780px}.links{font-size:13px}header .intro{color:#7eb2a3;font-size:12px;letter-spacing:1px}@media(max-width:720px){main{padding:20px 12px}h1{font-size:28px}.pair{grid-template-columns:1fr}}
</style><main><header><p class="intro">OMNIVIBE / 实际原生界面</p><h1>圆环、槽位与任务总览，一起补齐材质。</h1><p>十套游戏风格与三套经典主题。新增不同轮廓的核心底座、分层刻槽、嵌件、任务徽章与可拉伸边饰；任务总览加入轻量插画底层，边饰留在内容留白内。</p><aside>以下为实际 WPF 控件渲染，使用固定的示例任务。它展示界面与布局；状态不代表你的真实任务，静态截图不作为动画帧率证明。透明区域在图册中使用深色底衬托。</aside><nav><a href="core-before-after.png">十三套收起圆环对比</a><a href="review.md">改进与验证记录</a><a href="../settings-studio/index.html">新版设置与主题中心</a></nav></header><div class="toolbar"><button data-mode="expanded" aria-pressed="true">圆环与槽位</button><button data-mode="inventory" aria-pressed="false">任务总览</button><button data-mode="mini" aria-pressed="false">收起圆环</button></div>'''+''.join(cards)+'''<script>
document.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>{const mode=button.dataset.mode;document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));document.querySelectorAll('article').forEach(article=>article.querySelectorAll('img').forEach(img=>{const file=`screens/${article.dataset.slug}-${img.dataset.version}-${mode}.png`;img.src=file;img.parentElement.href=file;}));}));
</script></main></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')
    print('Published 13 real native theme comparisons, 104 WPF renders and core detail sheet.')

if __name__=='__main__':main()
