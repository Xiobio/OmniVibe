from pathlib import Path
import html
import json
import shutil
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/settings-studio'
SOURCE=ROOT/'artifacts/settings-studio/validation'

def main():
    report=json.loads((SOURCE/'report.json').read_text(encoding='utf-8'));assert report['passed']
    screens=OUT/'screens';screens.mkdir(parents=True,exist_ok=True)
    for file in SOURCE.glob('*.png'):
        with Image.open(file) as image:image.load()
        shutil.copy2(file,screens/file.name)
    shutil.copy2(SOURCE/'report.json',OUT/'validation.json')
    rows=json.loads((ROOT/'skins/native-v2/validation.json').read_text(encoding='utf-8'))['themes']
    parts=[('suite','整套效果'),('dock','任务圆环'),('overview','任务总览'),('terminal','Terminal'),('states','菜单与状态')]
    cards=[]
    for row in rows:
        name=html.escape(row['name']);slug=row['slug']
        cards.append(f'<article><h2>{name}</h2>'+''.join(f'<details><summary>{label}</summary><a href="screens/{slug}-{mode}.png"><img loading="lazy" src="screens/{slug}-{mode}.png" alt="{name} · {label}"></a></details>' for mode,label in parts)+'</article>')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OmniVibe · 设置与主题中心</title><style>:root{color-scheme:dark}body{margin:0;background:#0d1720;color:#ede8dc;font:15px/1.7 system-ui,"Microsoft YaHei UI",sans-serif}main{max-width:1180px;margin:auto;padding:30px 22px}h1{font-size:34px}p{color:#adc0cb}a{color:#a8d7c5}img{display:block;max-width:100%;height:auto;margin:12px 0 24px}article{border-top:1px solid #344953;padding:20px 0}h2{font-size:22px;margin:4px 0 16px}details{margin:12px 0}summary{cursor:pointer;color:#c4dbd0}nav{display:flex;gap:18px;flex-wrap:wrap}.note{background:#182b25;border-left:3px solid #b2d5c0;padding:12px 18px}</style><main><header><h1>设置与主题中心</h1><p>五个设置分区；十三套主题采用卡片浏览，并提供整套、圆环、总览、Terminal、菜单与状态五种预览，支持放大查看。</p><p class="note">页面截图来自实际 WPF 设置窗口。主题场景使用示例内容展示配色与布局，Terminal 使用实际背景资源；原生组件的完整真实渲染请查看<a href="../native-skin-refinement/index.html">原生组件对比图册</a>。</p><nav><a href="validation.json">六组自动验证</a><a href="review.md">实现说明</a></nav></header><a href="screens/settings-theme.png"><img src="screens/settings-theme.png" alt="主题中心实际窗口"></a><h2>卡片浏览全部主题</h2><a href="screens/settings-gallery.png"><img loading="lazy" src="screens/settings-gallery.png" alt="全部主题卡片"></a><h2>其他设置分区</h2>'''+''.join(f'<details><summary>{label}</summary><a href="screens/settings-{mode}.png"><img loading="lazy" src="screens/settings-{mode}.png" alt="{label}"></a></details>' for mode,label in [('ring','圆环与位置'),('layout','窗口与排列'),('keys','快捷键'),('general','常规与状态')])+''.join(cards)+'</main></html>'
    (OUT/'index.html').write_text(page,encoding='utf-8');print('Published settings UI and 65 suite component previews.')

if __name__=='__main__':main()
