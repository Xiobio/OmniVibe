"""Render the promo stage frame by frame with headless Chromium and encode with ffmpeg.
Usage: python render.py <work dir> <lang> [--preview t1,t2,...] [--start s --end s]
"""
import argparse
import shutil
import subprocess
from pathlib import Path

import imageio_ffmpeg
from playwright.sync_api import sync_playwright

ap = argparse.ArgumentParser()
ap.add_argument('work'); ap.add_argument('lang')
ap.add_argument('--preview', default=''); ap.add_argument('--start', type=float, default=0); ap.add_argument('--end', type=float, default=60)
ap.add_argument('--fps', type=int, default=30)
args = ap.parse_args()
work = Path(args.work).resolve(); stage = work / 'stage'
shutil.copy2(stage / f'config-{args.lang}.js', stage / 'config.js')
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()

with sync_playwright() as p:
    browser = p.chromium.launch(args=['--allow-file-access-from-files', '--disable-web-security', '--font-render-hinting=none', '--force-color-profile=srgb'])
    page = browser.new_page(viewport={'width': 1920, 'height': 1080}, device_scale_factor=1)
    page.goto((stage / 'index.html').as_uri())
    page.evaluate('ready()')
    page.wait_for_timeout(500)
    if args.preview:
        out = work / 'qa' / 'frames'; out.mkdir(parents=True, exist_ok=True)
        for t in [float(x) for x in args.preview.split(',')]:
            page.evaluate(f'seek({t})'); page.screenshot(path=str(out / f'{args.lang}-{t:05.2f}.png'))
        print('preview frames in', out)
    else:
        video = work / 'out' / f'video-{args.lang}.mp4'; video.parent.mkdir(parents=True, exist_ok=True)
        enc = subprocess.Popen([ffmpeg, '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', str(args.fps), '-c:v', 'mjpeg', '-i', '-',
                                '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(video)], stdin=subprocess.PIPE)
        n0, n1 = round(args.start * args.fps), round(args.end * args.fps)
        for n in range(n0, n1):
            page.evaluate(f'seek({n / args.fps})')
            enc.stdin.write(page.screenshot(type='jpeg', quality=95))
            if n % 150 == 0:
                print(args.lang, 'frame', n, flush=True)
        enc.stdin.close(); enc.wait()
        print('wrote', video)
    browser.close()
