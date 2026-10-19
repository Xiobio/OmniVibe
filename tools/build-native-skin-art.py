"""Build native UI material assets from the same editable frame source as Terminal.

The ring is an original shaded, engraved annulus. Its centre and exterior stay
transparent for task identity and desktop hit testing. No source art is edited.
"""
from pathlib import Path
import hashlib
import json
import math
import re
import numpy as np
from PIL import Image, ImageDraw
from terminal_frame_materials import Pen, build_frame, blend, rgb, gem, star

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'skins/native-v2'


def ring(row):
    size = 256; scale = 3; n = size * scale
    yy, xx = np.mgrid[:n, :n].astype(np.float32) / scale
    x, y = xx - 128, yy - 128; radius = np.hypot(x,y)
    theta = np.arctan2(y,x)
    rng = np.random.default_rng(491 + sum(map(ord,row['slug'])))
    family = row['family']
    teeth = {'mechanical':24,'tactical':8,'protocol':6,'equipment':12,'arsenal':9,'relic':16,'fantasy':12,'formation':8,'astral':4,'wonderland':12}[family]
    outer = 117 + 2*np.cos(theta*teeth)
    if family == 'mechanical': outer = 116 + 6*(np.cos(theta*24)>.18)
    elif family == 'tactical': outer = 121*math.cos(math.pi/8)/np.cos((theta+math.pi/8)%(math.pi/4)-math.pi/8)
    elif family == 'protocol': outer = 123*math.cos(math.pi/6)/np.cos((theta+math.pi/6)%(math.pi/3)-math.pi/6)
    elif family == 'relic': outer = 114 + 6*np.cos(theta*6)**4
    elif family == 'fantasy': outer = 112 + 11*np.maximum(0,np.cos(theta*6))**2
    elif family == 'formation': outer = np.minimum(124,100/(np.abs(np.cos(theta))**6+np.abs(np.sin(theta))**6)**(1/6))
    elif family == 'astral': outer = 108 + 16*np.maximum(0,np.cos(theta*4))**3
    elif family == 'wonderland': outer = 117 + 5*np.cos(theta*12)
    # Stepped metal / stone facets lit from the upper left, plus fine brushed grain.
    bevel = np.zeros_like(radius)
    for r,w,strength in [(119,1.5,.8),(114,2.4,.55),(108,1,.5),(97,3,.24),(83,1.3,.42),(73,3,.42),(66,1.5,.8)]:
        bevel += np.exp(-((radius-r)/w)**2)*strength
    bevel += np.exp(-((outer-radius-1.5)/1.4)**2)*.9
    light = np.clip(.40 + .32*(-x-y)/np.maximum(radius,1) + .26*bevel, .06, 1.1)
    grain = rng.normal(0,.038 if family=='relic' else .014,radius.shape)+.012*np.sin(radius*15+theta*8)
    accent = np.array(rgb(row['accent']),dtype=np.float32)
    surface = np.array(rgb(row['surface']),dtype=np.float32)
    base = .25*surface+.75*accent
    if family in ('tactical','protocol','relic','arsenal'): base = .52*surface+.48*accent
    if family == 'wonderland': base = np.array(blend(rgb(row['secondary']),rgb(row['background']),.64),dtype=np.float32)
    if family == 'formation': base = np.array(blend(rgb(row['elevated']),rgb(row['secondary']),.35),dtype=np.float32)
    colors = np.clip(base[None,None,:]*(light+grain)[:,:,None]+accent[None,None,:]*bevel[:,:,None]*.28,0,255)
    alpha = ((radius>=64)&(radius<=outer)).astype(np.uint8)*255
    texture = Image.fromarray(np.dstack((colors.astype(np.uint8),alpha)),'RGBA')
    p = Pen(size,size); p.im = texture; p.d = ImageDraw.Draw(p.im)
    a = rgb(row['accent']); b = rgb(row['border']); sec = rgb(row['secondary']); dark = rgb(row['background'])
    shine = blend(a,(255,255,240),.54); low = blend(b,dark,.62)
    for r,width,col in [(120,.6,b),(115,.7,shine),(112,1.1,low),(107,.6,a),(82,.7,low),(75,1.1,a),(68,.7,shine),(65,.7,low)]:
        p.ellipse((128-r,128-r,128+r,128+r),outline=col,width=width)
    def at(r, angle):
        t=math.radians(angle); return (128+math.cos(t)*r,128+math.sin(t)*r)
    # Raised sector plates, inset channels and family-specific relief occupy the
    # face, rather than leaving a flat metallic disc between concentric lines.
    sectors = 12 if family in ('mechanical','fantasy','astral') else 8 if family in ('tactical','equipment','formation') else 6 if family in ('relic','protocol','wonderland') else 9
    for i in range(sectors):
        angle=i*360/sectors-90; spread=360/sectors*.39
        shine_factor=.25+.20*math.cos(math.radians(angle+135))
        panel=blend(dark,a,max(.12,shine_factor))
        inner,outer_r=85,104 if family in ('protocol','formation','astral') else 109
        pts=[at(inner,angle-spread),at(outer_r-4,angle-spread),at(outer_r,angle-spread+3),at(outer_r,angle+spread-3),at(outer_r-4,angle+spread),at(inner,angle+spread)]
        p.poly(pts,panel,low)
        p.line(pts[1:4],blend(a,shine,.24),.7)
        p.line([pts[4],pts[5],pts[0]],blend(dark,b,.3),1.1)
        if family=='mechanical':
            p.line([at(88,angle-spread+3),at(98,angle-spread+3),at(98,angle-5),at(103,angle)],sec,.65)
            for off in [-5,0,5]:p.line([at(89,angle+spread-off-5),at(94,angle+spread-off-5)],a,.7)
        elif family=='tactical':
            for off in [-9,-5,-1,3,7]:p.line([at(88,angle+off),at(101,angle+off)],blend(b,dark,.25),1.2)
            p.line([at(102,angle-spread+2),at(102,angle+spread-2)],sec,.7)
        elif family=='protocol':
            p.poly([at(88,angle-5),at(102,angle-5),at(102,angle+1),at(88,angle+8)],blend(a,dark,.23),shine)
            p.line([at(91,angle+11),at(100,angle+7)],sec,.9)
        elif family=='equipment':
            p.line([at(87,angle-spread+2),at(87,angle+spread-2)],blend((93,54,30),a,.15),3)
            for off in range(-9,10,4):p.line([at(88,angle+off),at(91,angle+off+1.4)],shine,.6)
        elif family=='relic':
            for off in [-9,0,9]:
                p.line([at(87,angle+off-2),at(98,angle+off-2),at(98,angle+off+2),at(93,angle+off+2),at(93,angle+off)],blend(a,dark,.25),1.7)
                p.line([at(87,angle+off-1.6),at(97,angle+off-1.6)],shine,.5)
        elif family=='arsenal':
            p.poly([at(86,angle-7),at(110,angle-4),at(102,angle+5),at(93,angle+7)],blend(b,dark,.3),a)
            p.line([at(87,angle-6),at(108,angle-4)],shine,.8)
            p.line([at(88,angle+7),at(99,angle+2)],sec,1.5)
        elif family in ('fantasy','astral'):
            for j in range(3):
                line=[at(88+j*4,angle-spread+3+k*(2*spread-6)/14) for k in range(15)]
                p.line(line,shine if j==1 else a,.7)
            star(p,*at(97,angle),2.4,sec)
        elif family=='formation':
            for rr in [89,96]:
                for off in [-8,0,8]:
                    px,py=at(rr,angle+off);p.rounded((px-2,py-2,px+2,py+2),1,blend(sec,dark,.45),a,.5)
        elif family=='wonderland':
            for off in [-8,0,8]:
                px,py=at(96,angle+off);p.arc((px-4,py-4,px+4,py+4),160,350,shine,.9)
    ticks = 64 if family == 'tactical' else 48 if family in ('mechanical','astral') else 36
    for i in range(ticks):
        angle=i*360/ticks
        p.line([at(108 if i%4 else 103,angle),at(112,angle)],a if i%4 else shine,.65 if i%4 else 1.1)
    nodes = {'mechanical':6,'tactical':4,'protocol':6,'equipment':8,'arsenal':9,'relic':6,'fantasy':4,'formation':8,'astral':4,'wonderland':6}[family]
    for i in range(nodes):
        ang=i*360/nodes-90
        p.line([at(78,ang),at(105,ang)],low,6)
        p.line([at(78,ang-.45),at(105,ang-.45)],shine,.8)
        px,py=at(94,ang)
        if family=='tactical':
            p.rounded((px-5,py-5,px+5,py+5),1,blend(b,dark,.4),shine,.7)
            p.line([(px-2,py),(px+2,py)],sec,1)
        elif family=='relic':
            p.rect((px-6,py-6,px+6,py+6),blend(a,dark,.6),a,.8)
            p.line([(px-3,py+3),(px-3,py-3),(px+3,py-3),(px+3,py),(px,py),(px,py+3)],shine,.7)
        elif family=='equipment':
            p.ellipse((px-4,py-4,px+4,py+4),blend(b,dark,.2),shine,.9)
            p.line([(px-2,py-1),(px+2,py+1)],low,.8)
        elif family=='formation':
            p.rounded((px-6,py-5,px+6,py+5),2,blend(sec,dark,.35),a,1)
            p.line([(px-3,py-1),(px+3,py-1)],shine,.6)
        elif family=='wonderland':
            for offset in [-4,0,4]:p.ellipse((px+offset-4,py-3-abs(offset)*.3,px+offset+4,py+3),blend(sec,(235,255,249),.55),a,.6)
        elif family=='astral':
            star(p,px,py,8,shine);gem(p,px,py,3,sec)
        elif family=='protocol':
            p.poly([(px-7,py-4),(px+3,py-4),(px+7,py+4),(px-3,py+4)],a,shine)
        elif family=='arsenal':
            p.poly([at(78,ang-2.8),at(108,ang),at(84,ang+3),at(90,ang)],blend(a,dark,.45),shine)
            gem(p,px,py,3.8,sec)
        else:
            gem(p,px,py,5.7 if family=='fantasy' else 4.5,sec,'diamond')
    # Inner filigree distinguishes families at a glance even at small sizes.
    for i in range(nodes*2):
        ang=i*360/(nodes*2)
        if family in ('fantasy','astral','wonderland'):
            p.arc((46,46,210,210),ang+2,ang+360/(nodes*2)-3,a,.8)
            px,py=at(80,ang);p.ellipse((px-1,py-1,px+1,py+1),shine)
        elif family=='equipment':
            p.line([at(79,ang-1),at(83,ang+1)],shine,.7)
        elif family in ('relic','arsenal'):
            pts=[at(84,ang-3),at(87,ang-3),at(87,ang+3),at(84,ang+3)]
            p.line(pts,a,.75)
        else:
            p.line([at(84,ang),at(88,ang)],sec,.8)
    # All painted relief follows the distinct chassis silhouette.
    arr=np.array(p.im);arr[:,:,3]*=((radius>=64)&(radius<=outer))
    result=Image.fromarray(arr,'RGBA').resize((size,size),Image.Resampling.LANCZOS)
    # Clamp all antialiasing to a known transparent centre/exterior contract.
    arr=np.array(result);yy,xx=np.mgrid[:size,:size];r=np.hypot(xx-128,yy-128)
    arr[(r<62)|(r>125),3]=0
    return Image.fromarray(arr,'RGBA')


def main():
    rows=json.loads((ROOT/'skins/catalog.json').read_text(encoding='utf-8')); reports=[]
    fields=['slug','name','subtitle','dockTitle','overviewTitle','family','background','surface','elevated','text','muted','accent','secondary','border','running','waiting','ready','error','unknown','cardBackground','cardText']
    for line in (ROOT/'src/CodeManager/SkinCatalog.cs').read_text(encoding='utf-8-sig').splitlines():
        if re.search(r'new SkinDefinition\(Skin\.(InkJade|Midnight|Cinnabar),',line):
            row=dict(zip(fields,re.findall(r'"([^\"]*)"',line)))
            row['family']={'ink-jade':'relic','midnight':'astral','cinnabar':'arsenal'}[row['slug']]
            rows.append(row)
    for row in rows:
        folder=OUT/row['slug'];folder.mkdir(parents=True,exist_ok=True)
        frame_row=dict(row,slug={'ink-jade':'relic','midnight':'astral','cinnabar':'arsenal'}.get(row['slug'],row['slug']))
        frame=build_frame(frame_row);frame.save(folder/'frame.png',optimize=True)
        core=ring(row);core.save(folder/'core.png',optimize=True)
        alpha=np.array(core)[:,:,3];yy,xx=np.mgrid[:256,:256];r=np.hypot(xx-128,yy-128)
        assert not alpha[r<62].any() and not alpha[r>125].any()
        assert np.count_nonzero(alpha)>20000
        reports.append({'slug':row['slug'],'name':row['name'],'frame':str((folder/'frame.png').relative_to(ROOT)),'core':str((folder/'core.png').relative_to(ROOT)),'coreSha256':hashlib.sha256((folder/'core.png').read_bytes()).hexdigest(),'transparentCentreRadius':62,'transparentExteriorRadius':125,'originalArtworkChanged':False})
        print(row['slug'],flush=True)
    (OUT/'validation.json').write_text(json.dumps({'themes':reports,'source':'tools/terminal_frame_materials.py + tools/build-native-skin-art.py','nativeFrameNineSliceSourceCorner':96,'packaged':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
