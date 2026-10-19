"""Publish the actual full-scene Terminal assets and their generation prompts."""
import html
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/terminal-scene-gallery'
FONT='C:/Windows/Fonts/msyh.ttc'
SCENES={
    'hextech':'黄铜星仪与观星大厅', 'tactical':'岩壁掩体与装备平台',
    'protocol':'几何遗构与行动装置', 'adventure':'石拱地宫与冒险宝箱',
    'arsenal':'雕柱、梅枝与完整兵器阁', 'relic':'洞窟石梁、石柱与灵蕴石龛',
    'starlight':'蓝金星宫与云海露台', 'formation':'紫金棋局与悬浮备战大厅',
    'astral':'星图长廊与夜景观测台', 'wonderland':'青瓷仙阁与山水云庭'
}


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=json.loads((ROOT/'skins/catalog.json').read_text(encoding='utf-8'))
    assert len(rows)==10 and all(row.get('terminalArtwork') for row in rows)
    report=json.loads((ROOT/'themes/windows-terminal/assets/refined-v1/validation.json').read_text(encoding='utf-8'))
    results={r['slug']:r for r in report['themes']}
    source_hashes=set()
    cards=[]
    markdown=['# 十套 Terminal 完整环境画作','',
              '全部使用内置 imagegen 编辑原插画，另存独立 Terminal 源图。原生界面插画保留；正式背景继续使用原有 PNG / 96 帧 GIF 流程。','',
              '[实际终端背景总览](index.html) · [十套静态背景总图](overview.png)','',
              '| 主题 | 场景 | 独立源图 | 实际提示词 | 正式背景 |',
              '| --- | --- | --- | --- | --- |']
    sheet=Image.new('RGB',(1920,1680),'#101923')
    draw=ImageDraw.Draw(sheet)
    for i,row in enumerate(rows):
        slug=row['slug']; result=results[slug]
        assert result.get('fullEnvironmentScene') and not result.get('repeatedMarginMotifsOnIllustration')
        assert result['minimumAnsiContrast']>=4.5 and result['frames']==96 and result['protectedCenterStatic']
        source_hash=hashlib.sha256((ROOT/row['terminalArtwork']).read_bytes()).hexdigest()
        assert source_hash==result['terminalArtworkSha256'] and source_hash not in source_hashes
        source_hashes.add(source_hash)
        assert (ROOT/f'skins/{slug}/terminal-scene-v2.prompt.md').is_file()
        source='../../'+row['terminalArtwork']
        prompt=f'../../skins/{slug}/terminal-scene-v2.prompt.md'
        png=f'../../themes/windows-terminal/assets/refined-v1/{slug}-c-v1.png'
        gif=f'../../themes/windows-terminal/assets/refined-v1/{slug}-c-v1.gif'
        markdown.append(f'| {row["name"]} | {SCENES[slug]} | [PNG]({source}) | [提示词]({prompt}) | [静态]({png}) / [动态]({gif}) |')
        cards.append(f'''<article><h2>{html.escape(row['name'])}</h2><p>{SCENES[slug]} · 实际解码最低 ANSI 对比度 {result['minimumAnsiContrast']:.3f}:1</p><a href="{png}"><img loading="lazy" src="{png}" alt="{html.escape(row['name'])}正式终端背景"></a><nav><a href="{gif}">实际 GIF</a><a href="{source}">独立源图</a><a href="{prompt}">生成提示词</a><a href="../terminal-frame-refinement/{slug}-regular.png">带示例文字</a></nav></article>''')
        image=Image.open(ROOT/f'themes/windows-terminal/assets/refined-v1/{slug}-c-v1.png').convert('RGB')
        image.thumbnail((624,368),Image.Resampling.LANCZOS)
        x=i%3*640+8; y=i//3*420+35
        sheet.paste(image,(x,y))
        draw.text((x,y-29),row['name'],font=ImageFont.truetype(FONT,20),fill='#E8DFCB')
    sheet.save(OUT/'overview.png',optimize=True)
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OmniVibe · 十套完整环境画作</title><style>:root{color-scheme:dark}body{margin:0;background:#101923;color:#eee9dc;font:16px/1.7 system-ui,"Microsoft YaHei UI",sans-serif}main{max-width:1440px;margin:auto;padding:32px 24px}h1{font-size:34px}p{color:#b9c7cb}article{margin:40px 0;border-top:1px solid #34434b;padding-top:20px}h2{font-size:24px;margin:0}img{width:100%;height:auto;display:block;border-radius:8px}a{color:#a5d4c5}nav{display:flex;gap:22px;flex-wrap:wrap;margin:12px 0}.note{max-width:920px}header{margin-bottom:40px}</style><main><header><h1>十套完整环境画作</h1><p class="note">右侧主体与顶部、左侧、底部连成同一场景。此页直接读取正式终端静态背景；原始插画、实际 GIF 与提示词分别提供，深色与浅色主题均按实际文字配色校准。背景图中没有文字；“带示例文字”为离线合成预览。</p><nav><a href="overview.png">十套总图</a><a href="README.md">源图与提示词清单</a><a href="../../themes/windows-terminal/assets/refined-v1/validation.json">资源验证</a></nav></header>'''+''.join(cards)+'</main></html>'
    (OUT/'index.html').write_text(page,encoding='utf-8')
    (OUT/'README.md').write_text('\n'.join(markdown)+'\n',encoding='utf-8')
    print(json.dumps({'themes':len(rows),'gallery':str(OUT/'index.html'),'allScenesValidated':True}))


if __name__=='__main__':main()
