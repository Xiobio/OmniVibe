"""Assemble the promo stage: copies HTML/JS, theme art and writes per-language config.
Usage: python build.py <repo root> <work dir>   (work dir holds ui/ from PromoRender)
"""
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

repo, work = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
here = Path(__file__).resolve().parent
stage = work / 'stage'
(stage / 'assets' / 'art').mkdir(parents=True, exist_ok=True)
for name in ('index.html', 'promo.js'):
    shutil.copy2(here / 'stage' / name, stage / name)
shutil.copy2(repo / 'assets/brand/v4/icons/omnivibe-1024.png', stage / 'assets/icon.png')
rng = np.random.default_rng(3)
Image.fromarray((rng.random((256, 256)) * 255).astype('uint8'), 'L').save(stage / 'assets/grain.png')

timeline = json.loads((here / 'timeline.json').read_text(encoding='utf-8'))
schemes = {s['slug']: s['scheme'] for s in json.loads((repo / 'themes/windows-terminal/skins.json').read_text(encoding='utf-8-sig'))['skins']}

# Montage themes exclude packs built from official game art; names omit game titles.
THEMES = [
    ('relic', 'Relic Vault', 'Stone relics · Gilded spirit', '灵蕴法宝匣', '玄岩石龛 · 錾金灵蕴'),
    ('ink-jade', 'Jade Mechanism', 'Ink · Mechanics · Jade', '墨玉机关', '水墨 · 机关 · 玉石'),
    ('midnight', 'Midnight Lapis', 'Night · Lapis · Mountains', '玄夜青金', '夜色 · 青金 · 山海'),
    ('cinnabar', 'Cinnabar', 'Lacquer · Bronze · Hidden blades', '朱砂藏锋', '漆红 · 古铜 · 藏锋'),
    ('formation', 'Agent Bench', 'Violet board · Golden synergy', 'Agent 备战席', '蓝紫棋局 · 金色羁绊'),
    ('wonderland', 'Treasure Pouch', 'Celadon · Cloud embroidery', '三界百宝袋', '青瓷彩绘 · 云纹绣金'),
    ('tactical', 'Tactical Terminal', 'Dark alloy · Coordinates', '战术终端', '炭黑合金 · 坐标标尺'),
]
for slug, *_ in THEMES:
    shutil.copy2(repo / f'themes/windows-terminal/assets/refined-v1/{slug}-c-v1.png', stage / f'assets/art/{slug}.png')

TEXT = {
    'en': dict(
        hook1='Six agents. A dozen terminals.', hook2='Which one is waiting for you?',
        altTab='Alt + Tab. Again. And again.', tagline='Vibe code like you play.',
        brandSub='A game-inspired task inventory for parallel AI coding on Windows',
        captureTitle='Give every task a home.', captureSub='Drag a terminal in. It gets a numbered slot.',
        captureDone='Six tasks. Six slots. Always in the same place.',
        switchA='Out of the way until you need it.', switchB='Point. Click. You’re back in.', orPress='or press',
        radialTitle='Hold Alt + Q. Point. Release.', hold='hold',
        overviewTitle='See who’s waiting for you.', overviewSub='Claude Code & Codex status at a glance:\nrunning, needs input, done.',
        chips=['▷ Running', '! Needs input', '✓ Response ready', '× Error'],
        arrangeA='Arrange every window. One key.', arrangeB='Press it again to restore your layout.',
        themesTitle='Make it yours.', themesSub='13 coordinated themes for the launcher, overview and Windows Terminal.',
        collage='13 themes — or use your own images.',
        cta1='Free & open source · MIT · Windows', ctaStar='Star it on GitHub', ctaUrl='github.com/Xiobio/OmniVibe',
        ctaJoin='Early preview — ideas, issues and PRs welcome. Let’s build it together.',
        fine='Development preview · UI rendered from the app with sample tasks · terminal content is illustrative · not affiliated with any game publisher',
        waitingPrompt='Allow edit to api/webhooks/stripe.ts?  ❯ 1. Yes   2. No',
        tasks=['web · checkout flow', 'api · payments', 'tests · e2e suite', 'docs · release notes', 'infra · deploy', 'data · migration'],
        chaosTitles=['claude', 'codex', 'Windows PowerShell', 'claude', 'node', 'codex', 'claude', 'Windows PowerShell', 'codex'],
        prompts=['refactor the checkout form validation', 'fix the failing payment webhook tests', 'stabilize the e2e suite', 'draft release notes for v0.2.0', '', 'migrate the orders table'],
    ),
    'zh': dict(
        hook1='六个 Agent，十几个终端。', hook2='到底哪一个在等你？',
        altTab='Alt + Tab，再按，再按……', tagline='像玩游戏一样 Vibe Coding',
        brandSub='为多 Agent 并行开发打造的 Windows 任务装备栏',
        captureTitle='给每个任务一个家', captureSub='把终端拖进来，它就有了自己的编号槽位',
        captureDone='六个任务，六个槽位，位置永远不变',
        switchA='平时收起，需要时展开', switchB='指向，点击，直接回到任务', orPress='或者按',
        radialTitle='按住 Alt + Q，指向，松手', hold='按住',
        overviewTitle='一眼看出谁在等你', overviewSub='接入 Claude Code / Codex 状态\n执行中 · 等你确认 · 本轮已回复',
        chips=['▷ 正在执行', '! 等待你处理', '✓ 本轮已回复', '× 发生错误'],
        arrangeA='一个快捷键，排好所有窗口', arrangeB='再按一次，恢复原来的布局',
        themesTitle='换成你喜欢的样子', themesSub='13 套主题，入口、总览和 Windows Terminal 一起换装',
        collage='13 套主题，也可以换成你自己的图片',
        cta1='免费开源 · MIT · Windows', ctaStar='去 GitHub 点个 Star', ctaUrl='github.com/Xiobio/OmniVibe',
        ctaJoin='开发预览版，欢迎提想法、Issue 和 PR，一起把它做得更好',
        fine='开发预览版 · 界面为程序实际渲染（示例任务）· 终端内容为示意 · 与任何游戏厂商无关',
        waitingPrompt='允许修改 api/webhooks/stripe.ts？  ❯ 1. 是   2. 否',
        tasks=['前端 · 结算流程', '接口 · 支付回调', '测试 · 端到端', '文档 · 发布说明', '运维 · 部署脚本', '数据 · 迁移任务'],
        chaosTitles=['claude', 'codex', 'Windows PowerShell', 'claude', 'node', 'codex', 'claude', 'Windows PowerShell', 'codex'],
        prompts=['重构结算表单的校验逻辑', '修复支付回调的失败测试', '让端到端测试稳定下来', '起草 v0.2.0 的发布说明', '', '迁移订单表'],
    ),
}

for lang, folder in (('en', 'en'), ('zh', 'zh')):
    ui = work / 'ui' / folder
    rel = lambda p: Path('..', 'ui', folder, p).as_posix()
    timing = json.loads((ui / 'dock-motion' / 'timing.json').read_text(encoding='utf-8'))
    themes = []
    for slug, en_name, en_sub, zh_name, zh_sub in THEMES:
        scheme = schemes[slug]
        themes.append(dict(slug=slug, name=en_name if lang == 'en' else zh_name, sub=en_sub if lang == 'en' else zh_sub,
                           art=f'assets/art/{slug}.png', deck=rel(f'deck-{slug}.png'), fg=scheme['foreground'], accent=scheme['cursorColor'],
                           light=slug == 'wonderland'))
    config = dict(lang=lang, text=TEXT[lang], timeline=timeline, dockTiming=timing, themes=themes,
                  assets=dict(icon='assets/icon.png', inventory=rel('inventory-relic.png'),
                              fill=[rel(f'fill/{k}.png') for k in range(7)],
                              dock=[rel(f'dock-motion/{f["index"]:03d}.png') for f in timing],
                              radial=[rel(f'radial/{k:03d}.png') for k in range(90)]))
    (stage / f'config-{lang}.js').write_text('window.PROMO = ' + json.dumps(config, ensure_ascii=False) + ';\n', encoding='utf-8')
print('stage ready:', stage)
