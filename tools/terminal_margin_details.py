"""Quiet, static engravings for existing Terminal padding bands.

These are code-native motifs, not replacement illustrations or another frame.
The bands have gaps and fade before the text; no new runtime layer is needed.
"""
from __future__ import annotations

import math
import numpy as np
from PIL import Image
from terminal_frame_materials import Pen, rgb, star

DEPTH = 54


def band(row, length):
    p = Pen(length, 30)
    a, b = rgb(row['accent']), rgb(row['secondary'])
    ink = (*a, 68)
    shade = (*a, 30)
    glint = (*a, 93)
    secondary = (*b, 46)
    slug = row['slug']
    for i, x in enumerate(range(26, length - 24, 108)):
        # Small separated groups: no continuous inner rectangle or bright rail.
        p.line([(x - 19, 7), (x - 7, 7)], shade, .55)
        p.line([(x + 36, 7), (x + 57, 7)], shade, .55)
        if slug == 'ink-jade':
            p.line([(x-6,19),(x-6,6),(x+26,6),(x+26,17),(x+7,17),(x+7,11),(x+17,11)],ink,.7)
            p.arc((x+26,5,x+48,21),170,355,secondary,.7)
        elif slug == 'midnight':
            p.arc((x-7,3,x+24,23),35,295,ink,.7)
            points=[(x+22,17),(x+35,7),(x+49,16)]
            p.line(points,shade,.6)
            for cx,cy in points:star(p,cx,cy,2,secondary,inner=.2)
        elif slug == 'cinnabar':
            for j in range(4):
                q=x+j*12;p.line([(q,6),(q+8,12),(q,20)],ink if j%2 else secondary,.8)
            p.line([(x-8,22),(x+50,22)],shade,.6)
        elif slug == 'relic':
            # Recessed key frets, worn seal facets and scattered stone tooling.
            p.line([(x-4, 5), (x+23, 5), (x+23, 17), (x+6, 17),
                    (x+6, 10), (x+15, 10)], ink, .85)
            p.line([(x-4, 8), (x-4, 21), (x+27, 21)], shade, .6)
            p.line([(x+31, 7), (x+37, 12), (x+33, 20)], secondary, .6)
            if i % 3 == 1:
                p.line([(x+48, 12), (x+53, 10), (x+57, 14), (x+54, 18)], shade, .6)
            p.line([(x+1, 5), (x+7, 5)], glint, .5)
        elif slug == 'hextech':
            pts = [(x+11+math.cos(j*math.pi/3)*10, 13+math.sin(j*math.pi/3)*9) for j in range(6)]
            p.line(pts+[pts[0]], ink, .7)
            p.line([(x-12, 18), (x-3, 18), (x+1, 13)], secondary, .6)
            p.line([(x+21, 13), (x+29, 8), (x+43, 8)], ink, .6)
            p.ellipse((x+8, 10, x+14, 16), None, secondary, .7)
        elif slug == 'tactical':
            p.line([(x-7, 20), (x-7, 6), (x+40, 6)], ink, .7)
            for j in range(7):
                p.line([(x+j*6, 9), (x+j*6, 15 if j%3 else 19)], shade if j%3 else ink, .6)
            p.rect((x+45, 8, x+49, 11), secondary)
        elif slug == 'protocol':
            p.line([(x-8, 21), (x+4, 6), (x+31, 6)], ink, .8)
            p.line([(x+3, 21), (x+11, 12), (x+42, 12)], secondary, .6)
            for j in range(3):
                q=x+36+j*7
                p.line([(q, 22), (q+4, 17)], shade, .8)
        elif slug == 'adventure':
            p.rounded((x-4, 5, x+37, 22), 3, None, ink, .7)
            for j in range(5):
                q=x+2+j*7
                p.line([(q, 9), (q+3, 17)], shade, .65)
            for q in (x-9, x+44):
                p.ellipse((q-2, 11, q+2, 15), None, secondary, .65)
        elif slug == 'arsenal':
            p.line([(x-9, 20), (x+15, 5), (x+39, 20)], ink, .75)
            p.line([(x-4, 20), (x+15, 10), (x+34, 20)], shade, .6)
            p.line([(x+15, 6), (x+15, 23)], secondary, .6)
            p.line([(x+5, 19), (x+15, 15), (x+25, 19)], ink, .6)
        elif slug == 'starlight':
            p.arc((x-14, 2, x+44, 22), 18, 162, ink, .7)
            p.arc((x-6, 5, x+36, 21), 18, 162, shade, .55)
            star(p, x+15, 11, 6, secondary, inner=.22)
            p.ellipse((x+13.5, 9.5, x+16.5, 12.5), glint)
        elif slug == 'formation':
            for j in range(3):
                q=x+j*16
                p.rounded((q, 7, q+11, 19), 3, None, ink if j==1 else shade, .7)
                if j==1:
                    p.ellipse((q+4, 11, q+7, 14), secondary)
        elif slug == 'astral':
            points=[(x-8, 18), (x+5, 6), (x+22, 16), (x+39, 9), (x+53, 15)]
            p.line(points, shade, .55)
            for j,(cx,cy) in enumerate(points):
                p.ellipse((cx-1.2, cy-1.2, cx+1.2, cy+1.2), secondary if j%2 else ink)
            star(p, x+22, 16, 4, ink, inner=.2)
        elif slug == 'wonderland':
            p.arc((x-7, 6, x+17, 20), 155, 355, ink, .75)
            p.arc((x+8, 3, x+32, 20), 175, 355, secondary, .7)
            p.arc((x+25, 8, x+49, 21), 175, 335, ink, .65)
            p.line([(x+2, 22), (x+25, 22)], shade, .55)
    return p.image()


def margin_layer(row, width, height):
    layer = Image.new('RGBA', (width, height))
    # Enrich the three reported gaps only. The illustrated right side is intact.
    horizontal = band(row, width - 100)
    layer.alpha_composite(horizontal, (50, 24))
    layer.alpha_composite(horizontal.transpose(Image.Transpose.FLIP_TOP_BOTTOM), (50, height-54))
    vertical = band(row, height - 110).transpose(Image.Transpose.ROTATE_90)
    layer.alpha_composite(vertical, (24, 55))
    arr = np.array(layer)
    yy, xx = np.mgrid[:height, :width]
    # Uneven wear, not perfectly repeated UI glyphs. Keep details subdued as
    # they approach content and fade toward the existing right-hand scene.
    depth = np.minimum(np.minimum(yy, height-1-yy), xx)
    fade = np.clip((DEPTH-depth)/14, 0, 1)
    wear = .72 + .28*(.5+.5*np.sin(xx*.073+yy*.117))
    fade_right = np.clip((width*.88-xx)/(width*.2), .20, 1)
    arr[:,:,3] = np.rint(arr[:,:,3]*fade*wear*fade_right).astype(np.uint8)
    return Image.fromarray(arr, 'RGBA')
