"""Build production C-layout Terminal backgrounds and before/after evidence.

Pillow draws code-native decorative geometry and composes source illustrations.
Optional terminalArtwork keeps full-scene edits separate from native UI art.
Static/animated assets are below the Terminal foreground.
"""
from __future__ import annotations
import argparse
import hashlib
import html
import importlib.util
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps
from terminal_frame_materials import build_frame, rgb
from terminal_margin_details import margin_layer, DEPTH as MARGIN_DEPTH

ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'themes/windows-terminal/assets/refined-v1'
GALLERY=ROOT/'docs/terminal-frame-refinement'
REVIEW=ROOT/'artifacts/terminal-frame-refinement'
WIDTH,HEIGHT=1280,754
FRAMES,DURATION=96,150
spec=importlib.util.spec_from_file_location('comparison',ROOT/'tools/build-terminal-frame-comparison.py')
comparison=importlib.util.module_from_spec(spec);spec.loader.exec_module(comparison)


def linear(rgb):
    s=np.asarray(rgb,dtype=np.float32)/255
    return np.where(s<=.04045,s/12.92,((s+.055)/1.055)**2.4)


def srgb(value):
    return np.where(value<=.0031308,value*12.92,1.055*np.maximum(value,0)**(1/2.4)-.055)*255


def luminance(value):return linear(value)@np.array([.2126,.7152,.0722],dtype=np.float32)


def backdrop(row,scheme,details=True):
    art=ImageOps.fit(Image.open(ROOT/row.get('terminalArtwork',row['artwork'])).convert('RGB'),(WIDTH,HEIGHT),method=Image.Resampling.LANCZOS)
    arr=np.asarray(art,dtype=np.float32)
    xx=np.arange(WIDTH,dtype=np.float32)[None,:,None]/WIDTH
    # A reading veil at left and more visible illustration at right, calibrated
    # against every actual ANSI color rather than an arbitrary opacity cap.
    alpha=.20+.32*np.clip((xx-.25)/.75,0,1)**1.3
    if row.get('terminalArtwork'):
        yy=np.arange(HEIGHT,dtype=np.float32)[:,None,None]/HEIGHT
        # Architecture lives in the padding bands; retain atmosphere in the
        # reading area and preserve the established right-side focal balance.
        edge=np.maximum.reduce(np.broadcast_arrays(
            np.clip(1-xx/.10,0,1), np.clip(1-yy/.13,0,1), np.clip((yy-.86)/.14,0,1)))
        left_weight=1-np.clip((xx-.62)/.18,0,1)
        alpha=alpha+(0.78-alpha)*edge*left_weight
        details=False
    bg=np.array(rgb(row['background']),dtype=np.float32)
    arr=bg*(1-alpha)+arr*alpha
    return calibrate(row,scheme,arr,details)


def calibrate(row,scheme,arr,details=True):
    if details:
        layer=np.asarray(margin_layer(row,WIDTH,HEIGHT),dtype=np.float32)
        opacity=layer[:,:,3:4]/255
        arr=arr*(1-opacity)+layer[:,:,:3]*opacity
    bg=np.array(rgb(row['background']),dtype=np.float32)
    keys=['foreground','black','red','green','yellow','blue','purple','cyan','white',
          'brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite']
    text_lum=np.array([float(luminance(rgb(scheme[k]))) for k in keys])
    light=float(luminance(bg))>.5
    lin=linear(arr);lum=lin@np.array([.2126,.7152,.0722])
    target=4.80  # extra margin for GIF palette quantization
    if light:
        floor=max(target*(text_lum+.05)-.05)
        amount=np.clip((floor-lum)/np.maximum(1-lum,1e-5),0,1)
        lin=lin*(1-amount[:,:,None])+amount[:,:,None]
    else:
        ceiling=min((text_lum+.05)/target-.05)
        if ceiling<=0:raise ValueError('Uncalibrated dark palette')
        amount=np.minimum(1,ceiling/np.maximum(lum,1e-5))
        lin*=amount[:,:,None]
    return Image.fromarray(np.clip(np.rint(srgb(lin)),0,255).astype(np.uint8),'RGB'),keys


def contrast_report(row,scheme,decoded,keys):
    sample=np.asarray(decoded)[36:-36,40:-40]
    lum=luminance(sample)
    ratios={}
    for k in keys:
        f=float(luminance(rgb(scheme[k])))
        ratios[k]=float(np.min((np.maximum(f,lum)+.05)/(np.minimum(f,lum)+.05)))
    if min(ratios.values())<4.5:raise AssertionError(f"{row['slug']} contrast: {min(ratios.values())}")
    return {k:round(v,3) for k,v in ratios.items()}


def animate(row,base,frame_layer,frame_only=False):
    slug=row['slug'];base_rgb=np.asarray(base)
    yy,xx=np.mgrid[:HEIGHT,:WIDTH].astype(np.float32)
    qx=np.minimum(xx,WIDTH-1-xx);qy=np.minimum(yy,HEIGHT-1-yy);edge=np.minimum(qx,qy)
    allowed=(edge<24)|((qx<31)&(qy<31))
    # Separate palette budgets prevent bright metal/glow colors from being
    # introduced into the reading area by error diffusion.
    body_strip=Image.fromarray(base_rgb[~allowed][None,:,:],'RGB').quantize(colors=176,method=Image.Quantize.MEDIANCUT)
    body_colors=body_strip.getpalette()[:528]
    used=len(body_strip.getcolors())
    body_colors[used*3:528]=body_colors[:3]*(176-used)
    body_palette=Image.new('P',(1,1));body_palette.putpalette(body_colors+body_colors[:3]*80)
    quiet=np.array(base);quiet[allowed]=rgb(row['background'])
    body=Image.fromarray(quiet,'RGB').quantize(palette=body_palette,dither=Image.Dither.FLOYDSTEINBERG)
    indices_base=np.array(body);indices_base[indices_base>=176]=0
    rim_strip=Image.fromarray(base_rgb[allowed][None,:,:],'RGB').quantize(colors=48,method=Image.Quantize.MEDIANCUT)
    rim_colors=rim_strip.getpalette()[:144]
    rim_used=len(rim_strip.getcolors());rim_colors[rim_used*3:144]=rim_colors[:3]*(48-rim_used)
    indices_base[allowed]=np.asarray(rim_strip)[0]+176
    palette=body_colors+rim_colors+[0]*96
    accent=np.array(rgb(row['accent']),dtype=np.float32)
    secondary=np.array(rgb(row['secondary']),dtype=np.float32)
    light=slug=='wonderland'
    destination=np.array([252,244,206]) if not light else np.array([28,119,117])
    for i in range(31):
        c=accent if i<16 else secondary
        t=(i if i<16 else i-16)/(15 if i<16 else 14)
        v=c*(1-t)+destination*t
        palette[(224+i)*3:(225+i)*3]=list(np.clip(np.rint(v),0,255).astype(int))
    palette[765:768]=[0,0,0]
    fixed=Image.fromarray(indices_base,'P');fixed.putpalette(palette)
    fixed_rgb=np.asarray(fixed.convert('RGB'))
    y,x=np.nonzero(allowed)
    perimeter=2*(WIDTH+HEIGHT-2)
    along=np.where(qx<qy,np.where(xx>WIDTH/2,WIDTH+yy,perimeter-yy),
                   np.where(yy>HEIGHT/2,WIDTH+HEIGHT+WIDTH-xx,xx))
    pos=along[allowed];ed=edge[allowed]
    strip=fixed_rgb[allowed].astype(np.float32)
    # The highlights use the material's actual raised lips, not a generic glow
    # washed over the full border. Ornament shoulders catch a restrained sheen.
    shape=(np.asarray(frame_layer)[:,:,3]/255)[allowed]
    rail=np.exp(-((ed-3.5)/1.5)**2)*.75+np.exp(-((ed-12)/2.0)**2)*.24
    rail=np.maximum(rail,shape*.16)
    pictures=[];unique=set();changed_max=0
    for i in range(FRAMES):
        phase=i/FRAMES
        speed=1 if slug not in ('astral','relic') else -1
        distance=(pos-speed*phase*perimeter+perimeter/2)%perimeter-perimeter/2
        width={'tactical':95,'protocol':65,'adventure':230,'arsenal':100,'relic':260,'starlight':150,'formation':85,'astral':110,'wonderland':240}.get(slug,150)
        envelope=np.exp(-(distance/width)**2)
        second=np.exp(-(((pos-speed*phase*perimeter+perimeter*.5+perimeter/2)%perimeter-perimeter/2)/width)**2)
        alpha=np.clip(rail*(envelope*.88+second*.46),0,.9)
        if slug=='protocol':alpha*=((np.floor(pos/13)%4)!=0)
        if slug=='tactical':alpha*=np.where(ed<8,1,.25)
        if slug=='formation':alpha*=.4+.6*(np.cos(pos/36*math.tau)**8)
        if slug=='relic':alpha*=.64+.16*math.sin(phase*math.tau)
        if slug=='astral':alpha*=.4+.6*np.maximum(0,np.cos(pos*.023+phase*math.tau))**4
        if slug=='wonderland':alpha*=.65
        glow=accent*(1-.52)+destination*.52
        if slug in ('hextech','starlight','formation'):glow=secondary*.4+destination*.6
        colored=np.rint(strip*(1-alpha[:,None])+glow*alpha[:,None]).astype(np.uint8)
        quant=Image.fromarray(colored[None,:,:],'RGB').quantize(palette=fixed,dither=Image.Dither.NONE)
        frame=indices_base.copy();active=alpha>.004
        frame[y[active],x[active]]=np.asarray(quant)[0,active]
        changed_max=max(changed_max,int(np.count_nonzero(frame!=indices_base)))
        picture=Image.fromarray(frame,'P');picture.putpalette(palette);pictures.append(picture)
    path=ASSETS/(f'{slug}-frame-only-v1.gif' if frame_only else f'{slug}-c-v1.gif')
    pictures[0].save(path,save_all=True,append_images=pictures[1:],duration=DURATION,loop=0,disposal=1,optimize=True,transparency=255)
    gif=Image.open(path)
    assert gif.n_frames==FRAMES and gif.info.get('loop')==0
    for i in range(FRAMES):
        gif.seek(i);decoded=np.asarray(gif.convert('RGB'))
        if not np.array_equal(decoded[~allowed],fixed_rgb[~allowed]):raise AssertionError('Animation changed reading area')
        unique.add(hashlib.sha256(decoded.tobytes()).hexdigest())
    if len(unique)!=FRAMES:raise AssertionError('Frozen animation')
    gif.seek(FRAMES//4)
    return gif.convert('RGB'),dict(frames=FRAMES,durationMs=DURATION,uniqueDecodedFrames=len(unique),
                protectedCenterStatic=True,fixedBackgroundDither=True,maximumChangedPixels=changed_max,bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest(),file=str(path.relative_to(ROOT)))


def fixture(row,body,mode='regular'):
    w,h=comparison.SIZES[mode]
    resized=body.resize((w,h-comparison.TITLE),Image.Resampling.LANCZOS)
    fg,alpha=comparison.glyphs(row,w,h-comparison.TITLE)
    arr=np.asarray(resized,dtype=np.float32)
    return comparison.chrome(comparison.mix(arr,fg,alpha),row,w,h)


def showcase(row,new,old):
    w=1944;im=Image.new('RGB',(w,1020),'#101923');d=ImageDraw.Draw(im)
    font=ImageFont.truetype(comparison.UI,28);small=ImageFont.truetype(comparison.UI,17)
    d.text((24,15),row['name']+' · C 方案细化',font=font,fill='#F1EBDD')
    d.text((24,61),row['subtitle']+'  /  原版与新版使用同一段示例文字；新版直接读取可应用背景资源',font=small,fill='#AFBFCA')
    for n,(label,pic) in enumerate([('原版 C · 线框与小角标',old),('新版 C · 材质、结构、专属角饰',new)]):
        x=24+n*960
        d.text((x,102),label,font=ImageFont.truetype(comparison.UI,22),fill='#BFDDCE' if n else '#C3C5C0')
        im.paste(pic.resize((936,585),Image.Resampling.LANCZOS),(x,142))
        d.text((x,748),'左上角 · 原尺寸细节',font=small,fill='#AFBFCA')
        crop=pic.crop((0,comparison.TITLE,936,comparison.TITLE+220))
        im.paste(crop,(x,780))
    REVIEW.mkdir(parents=True,exist_ok=True)
    im.save(REVIEW/f"{row['slug']}-before-after.png",optimize=True)


def gallery(rows,reports):
    rows=json.loads((ROOT/'themes/windows-terminal/classic-palettes.json').read_text(encoding='utf-8'))+json.loads((ROOT/'skins/catalog.json').read_text(encoding='utf-8'))
    rows=list({row['slug']:row for row in rows}.values())
    cards=[]
    for row in rows:
        slug=row['slug'];name=html.escape(row['name'])
        image=f'{slug}-regular.png'
        if not (GALLERY/image).exists():raise FileNotFoundError(GALLERY/image)
        cards.append(f'<article id="{slug}"><h2>{name}</h2><a href="{image}"><img loading="lazy" src="{image}" alt="{name}"></a><p><a href="../../themes/windows-terminal/assets/refined-v1/{slug}-c-v1.gif">查看可选背景动效</a></p></article>')
    page="""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OmniVibe · 13 套 Terminal 预览</title><style>body{margin:0;background:#101923;color:#e9eee9;font:16px/1.7 system-ui}main{max-width:1280px;margin:auto;padding:28px}a{color:#a6dbc7}article{margin:32px 0;border-top:1px solid #35454e}img{display:block;width:100%;height:auto}nav{display:flex;gap:20px;flex-wrap:wrap}</style><main><h1>13 套 Terminal 正式预览</h1><p>实际背景配离线示例文字，用于展示外观；不代表真实任务状态或实际显示器 DPI 测试。每套保留一张常规预览，完整运行素材与可选动效均保持原样。</p><nav><a href="../project-kit/showcase.md">整套效果展示</a><a href="review.md">设计与验证说明</a><a href="https://github.com/Xiobio/OmniVibe/tree/v0.1.1-preview/docs/terminal-frame-refinement">历史尺寸与前后对比</a></nav>"""+''.join(cards)+'</main></html>\n'
    (GALLERY/'index.html').write_text(page,encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--skin',default='');parser.add_argument('--review-variants',action='store_true');args=parser.parse_args()
    ASSETS.mkdir(parents=True,exist_ok=True);GALLERY.mkdir(parents=True,exist_ok=True)
    rows=json.loads((ROOT/'skins/catalog.json').read_text(encoding='utf-8'))
    schemes={r['slug']:r['scheme'] for r in json.loads((ROOT/'themes/windows-terminal/skins.json').read_text(encoding='utf-8'))['skins']}
    reports=[]
    for row in rows:
        if args.skin and row['slug']!=args.skin:continue
        source=ROOT/row['artwork'];source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
        terminal_source=ROOT/row.get('terminalArtwork',row['artwork'])
        terminal_hash=hashlib.sha256(terminal_source.read_bytes()).hexdigest()
        background,keys=backdrop(row,schemes[row['slug']])
        frame=build_frame(row,WIDTH,HEIGHT)
        full=Image.alpha_composite(background.convert('RGBA'),frame).convert('RGB')
        full.save(ASSETS/f"{row['slug']}-c-v1.png",optimize=True)
        plain,_=calibrate(row,schemes[row['slug']],np.asarray(Image.new('RGB',(WIDTH,HEIGHT),row['background']),dtype=np.float32))
        noart=Image.alpha_composite(plain.convert('RGBA'),frame).convert('RGB')
        noart.save(ASSETS/f"{row['slug']}-frame-only-v1.png",optimize=True)
        current,report=animate(row,full,frame)
        _,noart_report=animate(row,noart,frame,frame_only=True)
        ratios=contrast_report(row,schemes[row['slug']],current,keys)
        margin=np.asarray(margin_layer(row,WIDTH,HEIGHT))[:,:,3]
        assert not margin[MARGIN_DEPTH:HEIGHT-MARGIN_DEPTH,MARGIN_DEPTH:].any(), 'Margin detail reached the central scene'
        for region in (margin[24:54,50:WIDTH//2],margin[55:HEIGHT-55,24:54],margin[HEIGHT-54:HEIGHT-24,50:WIDTH//2]):
            assert np.count_nonzero(region)>200, 'Requested margin band has no details'
        previous=ROOT/f"artifacts/terminal-frame-comparison/{row['slug']}-C-regular.png"
        original=Image.open(previous).convert('RGB') if previous.exists() else None
        for mode in (('regular','compact') if args.review_variants else ('regular',)):
            result=fixture(row,current,mode);target=GALLERY if mode=='regular' else REVIEW;target.mkdir(parents=True,exist_ok=True);result.save(target/f"{row['slug']}-{mode}.png",optimize=True)
            if mode=='regular':
                if args.review_variants and original is not None:showcase(row,result,original)
                if args.review_variants:REVIEW.mkdir(parents=True,exist_ok=True);result.resize((1920,1200),Image.Resampling.LANCZOS).save(REVIEW/f"{row['slug']}-hidpi.png",optimize=True)
        # Strict geometry check with the same foreground glyph mask used above.
        fa=np.asarray(frame)[:,:,3]>0
        fg,alpha=comparison.glyphs(row,WIDTH,HEIGHT)
        if np.any(fa&(alpha>0)):raise AssertionError(f"{row['slug']} decoration reaches glyphs")
        if hashlib.sha256(source.read_bytes()).hexdigest()!=source_hash:raise AssertionError('Original artwork changed')
        report.update(slug=row['slug'],name=row['name'],sourceSha256=source_hash,sourceUnmodified=True,
                      terminalArtwork=str(terminal_source.relative_to(ROOT)),terminalArtworkSha256=terminal_hash,
                      fullEnvironmentScene=bool(row.get('terminalArtwork')),
                      cLayout=True,foregroundGlyphIntersectionPixels=0,referenceWidth=WIDTH,referenceHeight=HEIGHT,
                      safeDecorationDepth=31,allAnsiContrast=ratios,minimumAnsiContrast=min(ratios.values()),
                      staticMarginDetailDepth=MARGIN_DEPTH,marginDetailBands=['top','left','bottom'],marginDetailsAnimated=False,
                      repeatedMarginMotifsOnIllustration=not bool(row.get('terminalArtwork')),
                      artworkToneMappedForReadability=True,pixelShaderRequired=False,frameOnlyAnimation=noart_report)
        reports.append(report)
        (ASSETS/f"{row['slug']}.validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({'skin':row['slug'],'minimumContrast':report['minimumAnsiContrast'],'bytes':report['bytes']}),flush=True)
    if not args.skin:
        output={'version':1,'layout':'C','themes':reports,'count':len(reports),'width':WIDTH,'height':HEIGHT,'frames':FRAMES,
                'renderingLayer':'Terminal background Image below foreground','packaged':False,'liveSettingsChangedDuringBuild':False}
        (ASSETS/'validation.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        gallery(rows,reports)
    else:
        # Keep aggregate evidence current when rebuilding just one scene.
        aggregate=ASSETS/'validation.json'
        if aggregate.exists():
            output=json.loads(aggregate.read_text(encoding='utf-8'))
            replacements={item['slug']:item for item in reports}
            present={item['slug'] for item in output['themes']}
            output['themes']=[replacements.get(item['slug'],item) for item in output['themes']]+[item for item in reports if item['slug'] not in present]
            output['count']=len(output['themes'])
            aggregate.write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
