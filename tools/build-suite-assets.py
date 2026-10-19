"""Extract approved transparent atlas cells without resampling; validate every pack.

Original atlases remain in artifacts; exact built-in prompts and source hashes
travel with the pack. This is technical sprite extraction, not repainting.
"""
from pathlib import Path
import argparse, hashlib, json, math, shutil
from PIL import Image, ImageDraw, ImageFont
import numpy as np
from scipy import ndimage
import requests

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'skins/loadouts/suites-v1'
MANIFEST = BASE / 'catalog.json'

ITEMS = {
 'ink-jade': [('jade-sword','玉魄剑'),('crane-fan','墨鹤羽扇'),('armillary','青铜浑仪'),('jade-flute','碧玉箫'),('clockwork-crossbow','机关连弩'),('lion-censer','狻猊香炉'),('bamboo-scroll','竹简玉印'),('lotus-lantern','玉莲灯'),('dragon-key','蟠龙铜钥')],
 'midnight': [('moon-halberd','弦月戟'),('star-compass','青金星盘'),('celestial-fan','星图折扇'),('crane-lantern','银鹤宫灯'),('dragon-orb','苍龙星珠'),('night-zither','玄夜古琴'),('meteor-dagger','陨铁短匕'),('whale-pendant','银鲸佩'),('lunar-tome','月华秘卷')],
 'cinnabar': [('dragon-saber','赤绫龙刀'),('war-drum','朱漆战鼓'),('gourd-flask','鎏金酒葫'),('phoenix-mask','丹凤面具'),('tiger-tally','青铜虎符'),('lacquer-crossbow','赤漆弩'),('temple-bell','红缨铜铃'),('lotus-crown','焰莲冠'),('dragon-brush','朱砂龙笔')],
 'relic': [('iron-staff','金箍铁杖 · 演绎'),('healing-gourd','赤漆宝葫 · 演绎'),('gold-cicada','金蝉 · 演绎'),('wind-pearl','定风灵珠 · 演绎'),('ritual-bell','辟火铜钟 · 演绎'),('leaf-fan','蕉叶宝扇 · 演绎'),('monkey-mask','灵猴面甲 · 演绎'),('relic-pagoda','古刹灵塔 · 演绎'),('dragon-circlet','双龙金冠 · 演绎')],
 'hextech': [('shark-launcher','金克丝 · 鲨齿火箭炮'),('hex-gauntlet','蔚 · 海克斯拳套'),('long-rifle','凯特琳 · 精密长枪'),('hex-hammer','杰斯 · 水晶战锤'),('time-blade','艾克 · 时光刃'),('fox-orb','阿狸 · 灵狐宝珠'),('wind-katana','亚索 · 御风长刀'),('frost-bow','艾希 · 臻冰弓'),('soul-lantern','锤石 · 幽魂灯笼')],
 'tactical': [('mcx','MCX · 短突击步枪'),('m4','M4 · 战术卡宾枪'),('awm','AWM · 精密狙击枪'),('mp5','MP5 · 冲锋枪'),('ak','AK · 木托突击步枪'),('shotgun','泵动霰弹枪'),('lmg','弹链轻机枪'),('combat-knife','战术匕首'),('recon-drone','侦察四轴无人机')],
 'adventure': [('demon-sword','狂战士 · 魔剑'),('violet-katana','剑宗 · 紫刃'),('crystal-staff','魔法师 · 晶杖'),('silver-revolver','神枪手 · 银色左轮'),('holy-cross','圣职者 · 圣十字'),('iron-gauntlets','格斗家 · 铁拳'),('twin-daggers','暗夜使者 · 双匕'),('emerald-bow','弓箭手 · 翡翠弓'),('dragon-spear','魔枪士 · 龙枪')],
 'starlight': [('sun-staff','孙悟空 · 金箍长棍'),('mulan-swords','花木兰 · 双形重剑'),('sun-cannon','孙尚香 · 机巧弩炮'),('lotus-sword','李白 · 青莲剑'),('ice-staff','王昭君 · 冰雪法杖'),('butterfly-fan','貂蝉 · 蝶舞扇'),('jade-rings','大乔 · 潮汐灯'),('flame-spear','哪吒 · 火尖枪'),('guan-blade','关羽 · 青龙长刀')],
 'formation': [('feather-knight','羽饰小骑士 · 原创棋灵'),('river-sprite','蓝河灵 · 原创棋灵'),('tiny-dragon','紫晶幼龙 · 原创棋灵'),('forest-fox','翡翠灵狐 · 原创棋灵'),('gold-penguin','金冠小企鹅 · 原创棋灵'),('horned-cub','双角石狮 · 原创棋灵'),('star-owl','月帽星鸮 · 原创棋灵'),('mushroom-sprite','蘑菇精灵 · 原创棋灵'),('cloud-ram','云团小羊 · 原创棋灵')],
 'astral': [('anemo-lyre','风吟诗琴 · 演绎'),('geo-spear','岩纹长枪 · 演绎'),('electro-sword','雷光薙刀 · 演绎'),('dendro-lamp','草木灵灯 · 演绎'),('hydro-cane','水华手杖 · 演绎'),('pyro-claymore','赤焰大剑 · 演绎'),('cryo-bow','霜星长弓 · 演绎'),('star-compass','星旅罗盘 · 演绎'),('fairy-bottle','流光仙灵瓶 · 演绎')],
 'wonderland': [('sword-knight','青衫剑侠 · 原创'),('fox-maiden','灵狐少女 · 原创'),('dragon-prince','碧海龙子 · 原创'),('bone-sprite','紫蝶骨灵 · 原创'),('tiger-warrior','虎头武者 · 原创'),('dancing-fairy','彩带天女 · 原创'),('rabbit-spirit','月兔灵宠 · 原创'),('lotus-fairy','莲叶花妖 · 原创'),('tortoise-general','碧甲龟将 · 原创')],
}

def read_manifest():
    return json.loads(MANIFEST.read_text(encoding='utf-8-sig'))

def save_manifest(m):
    classic = {'InkJade':('墨玉机关','水墨 · 机关 · 玉石'),'Midnight':('玄夜青金','夜色 · 青金 · 山海'),'Cinnabar':('朱砂藏锋','漆红 · 古铜 · 藏锋')}
    for p in m['packs']:
        if p['skin'] in classic: p['title'],p['subtitle']=classic[p['skin']]
    MANIFEST.write_text(json.dumps(m, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def font(size):
    for p in ['C:/Windows/Fonts/msyh.ttc','C:/Windows/Fonts/simhei.ttf']:
        if Path(p).exists(): return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def sheet(pack):
    canvas = Image.new('RGB', (1050, 1410), '#172128'); d=ImageDraw.Draw(canvas)
    d.text((24,12), pack['title'], fill='#eaddbd',font=font(26))
    for n,item in enumerate(pack['items']):
        x=(n%3)*350;y=60+(n//3)*450
        # Neutral checkerboard demonstrates genuine alpha and readability.
        for a in range(0,330,22):
            for b in range(0,300,22):d.rectangle((x+10+a,y+b,x+31+a,y+21+b), fill=('#1f2b34' if (a//22+b//22)%2 else '#27353e'))
        img=Image.open(BASE/item['image']).convert('RGBA');img.thumbnail((306,290),Image.Resampling.LANCZOS)
        canvas.paste(img,(x+175-img.width//2,y+150-img.height//2),img)
        label=f'{n+1} {item["name"]}';label_font=font(16)
        while d.textlength(label,font=label_font)>324:label=label[:-2]+'…'
        d.text((x+14,y+306), label, fill='#e9dfca',font=label_font)
        # Render production UI target sizes as a second visual evidence row.
        for size,left in [(56,x+20),(110,x+100)]:
            mini=Image.open(BASE/item['image']).convert('RGBA');mini.thumbnail((size,size),Image.Resampling.LANCZOS)
            canvas.paste(mini,(left,y+332),mini)
    out=ROOT/'artifacts/suite-assets/contact-sheets';out.mkdir(parents=True,exist_ok=True)
    canvas.save(out/(pack['slug']+'.png'))

def extract(slug, source, prompt):
    m=read_manifest();pack=next(p for p in m['packs'] if p['slug']==slug)
    dest=BASE/slug;dest.mkdir(parents=True,exist_ok=True)
    originals=ROOT/'artifacts/suite-assets/atlases'; originals.mkdir(parents=True,exist_ok=True)
    if Path(source).resolve() != (originals/(slug+'.png')).resolve():
        shutil.copy2(source,originals/(slug+'.png'))
    (originals/(slug+'.prompt.txt')).write_text(prompt,encoding='utf8')
    im=Image.open(source).convert('RGBA'); items=[]
    # Generators leave small fragments across nominal grid boundaries. Assign
    # complete connected silhouettes by centroid, then extract from the full
    # atlas. This preserves a sword tip crossing a nominal grid line and excludes
    # a neighbouring weapon's fragments rather than clipping or repainting it.
    alpha=np.asarray(im.getchannel('A'))
    labels,count=ndimage.label(alpha>12)
    sizes=np.bincount(labels.ravel()); sizes[0]=0
    objects=ndimage.find_objects(labels)
    components=[]
    for lab in range(1,count+1):
        if sizes[lab]<25:continue
        ys,xs=objects[lab-1]
        cy,cx=ndimage.center_of_mass(alpha,labels,lab)
        components.append((lab,int(sizes[lab]),cx,cy))
    for n,(id,name) in enumerate(ITEMS[slug]):
        c=n%3;r=n//3
        own=[v for v in components if min(2,int(v[2]*3/im.width))==c and min(2,int(v[3]*3/im.height))==r]
        if not own:raise ValueError(f'empty {slug} {id}')
        main=max(own,key=lambda v:v[1]); chosen=[v[0] for v in own if v[1]>=main[1]*.004 and math.hypot((v[2]-main[2])/(im.width/3),(v[3]-main[3])/(im.height/3))<.55]
        mask=ndimage.binary_dilation(np.isin(labels,chosen),iterations=1);rgba=np.array(im);rgba[:,:,3]=np.where(mask,rgba[:,:,3],0)
        clean=Image.fromarray(rgba);bbox=clean.getchannel('A').getbbox();content=clean.crop(bbox)
        # Pad to at least 512px for consistent decoding; preserve source pixels.
        side=max(512,content.width+24,content.height+24)
        dst=Image.new('RGBA',(side,side));dst.paste(content,((side-content.width)//2,(side-content.height)//2))
        target=dest/(id+'.png');dst.save(target,optimize=True)
        items.append({'id':slug+'-'+id,'name':name,'kind':'原创风格器物' if slug not in ('formation','wonderland') else '原创风格角色',
         'image':f'{slug}/{id}.png','source':f'original-atlas:{slug}',
         'provenance':'OmniVibe 原创 AI 辅助游戏风格演绎；内置 imagegen 生成透明九实体图集，按网格独立提取；不是官方游戏实物或官方皮肤。',
         'sourcePixels':[im.width,im.height],'nativeContentPixels':[content.width,content.height],
         'processing':'Complete native silhouettes separated by alpha connectivity and atlas cell centroids, without resampling; transparent padding only.'})
    pack['items']=items
    pack['artDirection']='九个独立可辨识实体；原创游戏风格演绎，非官方素材'
    pack['generation']={'tool':'built-in image_gen.imagegen','prompt':prompt,'atlasSha256':hashlib.sha256(Path(source).read_bytes()).hexdigest(),'atlasNativePixels':[im.width,im.height]}
    save_manifest(m);sheet(pack)

def validate():
    m=read_manifest();results=[]
    for pack in m['packs']:
        hashes=[];images=[]
        for item in pack['items']:
            path=BASE/item['image'];img=Image.open(path).convert('RGBA');alpha=img.getchannel('A');hist=alpha.histogram(); sha=hashlib.sha256(path.read_bytes()).hexdigest();hashes.append(sha)
            info={'id':item['id'],'path':str(path.relative_to(ROOT)).replace('\\','/'),'pixels':list(img.size),'sha256':sha,'transparentFraction':hist[0]/(img.width*img.height),'visibleFraction':1-hist[0]/(img.width*img.height),'alphaBounds':alpha.getbbox(),'nativeContentPixels':item.get('nativeContentPixels')}
            assert hist[0]>0 and sum(hist[1:])>0, info
            assert min(img.size)>=128 and max(img.size)>=512,info
            assert item.get('provenance'),info
            images.append(info)
        ready=len(images)==9 and len(set(hashes))==9
        if images:sheet(pack)
        results.append({'skin':pack['skin'],'slug':pack['slug'],'ready':ready,'items':images,'contactSheet':f'artifacts/suite-assets/contact-sheets/{pack["slug"]}.png' if images else None})
    report={'packsReady':sum(r['ready'] for r in results),'packsExpected':13,'assets':sum(len(r['items']) for r in results),'results':results}
    p=ROOT/'artifacts/suite-assets';p.mkdir(parents=True,exist_ok=True);(p/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:v for k,v in report.items() if k!='results'}))

def import_characters():
    m=read_manifest()
    archive=ROOT/'artifacts/suite-assets/source-originals';archive.mkdir(parents=True,exist_ok=True)
    api=requests.get('https://valorant-api.com/v1/agents?isPlayableCharacter=true',timeout=40);api.raise_for_status()
    (archive/'valorant-api.json').write_bytes(api.content)
    agents={x['displayName']:x for x in api.json()['data']}
    choices=[('Jett','捷风'),('Sage','贤者'),('Reyna','蕾娜'),('Raze','雷兹'),('Cypher','零'),('Killjoy','奇乐'),('Sova','猎枭'),('Omen','幽影'),('Viper','蝰蛇')]
    pack=next(p for p in m['packs'] if p['skin']=='Protocol');items=[];dest=BASE/pack['slug'];dest.mkdir(parents=True,exist_ok=True)
    for english,chinese in choices:
        agent=agents[english];slug=english.lower();url=agent['fullPortrait']
        original=archive/(slug+'.png')
        if not original.exists():
            b=requests.get(url,timeout=40);b.raise_for_status();original.write_bytes(b.content)
        img=Image.open(original).convert('RGBA');native=img.size;img=img.crop(img.getchannel('A').getbbox());pixels=img.size
        img.thumbnail((1200,1200),Image.Resampling.LANCZOS)
        out=Image.new('RGBA',(img.width+24,img.height+24));out.paste(img,(12,12));out.save(dest/(slug+'.png'),optimize=True)
        items.append({'id':'protocol-'+slug,'name':chinese+' · '+english,'kind':'特工 · 原游戏立绘','image':f'protocol/{slug}.png','source':url,
         'sourcePage':f'https://playvalorant.com/en-us/agents/{slug}/','sourceSha256':hashlib.sha256(original.read_bytes()).hexdigest(),'sourcePixels':list(native),'nativeContentPixels':list(pixels),
         'provenance':'Riot Games《无畏契约》原游戏特工立绘，Valorant-API社区镜像；版权属于Riot Games，不属于OmniVibe开源代码许可证；非官方合作。',
         'processing':'Transparent bounds trimmed; Lanczos downsample to max 1200 content edge; 12px transparent safety margin.'})
        print('imported',slug,flush=True)
    pack['items']=items;pack['artDirection']='原游戏特工透明立绘；权利归属与来源逐项保留'
    save_manifest(m);sheet(pack)
    old=ROOT/'skins/loadouts/naraka';catalog=json.loads((old/'catalog.json').read_text(encoding='utf8'))
    pack=next(p for p in m['packs'] if p['skin']=='Arsenal');items=[];dest=BASE/pack['slug'];dest.mkdir(parents=True,exist_ok=True)
    for item in catalog['items']:
        source=old/item['character_image'];img=Image.open(source).convert('RGBA');native=img.size
        img=img.crop(img.getchannel('A').getbbox());pixels=img.size;img.thumbnail((1024,1024),Image.Resampling.LANCZOS)
        out=Image.new('RGBA',(img.width+24,img.height+24));out.paste(img,(12,12));out.save(dest/(item['id']+'.png'),optimize=True)
        items.append({'id':item['id'],'name':item['character_name'],'kind':'角色持武器 · 高清演绎','image':f'arsenal/{item["id"]}.png','source':item['character_source'],
         'sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest(),'sourcePixels':list(native),'nativeContentPixels':list(pixels),
         'provenance':'复用OmniVibe已有characters-v2：参考NetEase永劫无间官方角色立绘，由内置imagegen生成透明持械演绎。不是原始官方渲染，角色权利属于NetEase。',
         'processing':'Existing approved character render reused; transparent bounds trimmed and downsampled to max 1024 content edge; 12px safety margin.'})
    pack['items']=items;pack['artDirection']='既有九位持械角色高清透明演绎；保留旧配装ID兼容'
    save_manifest(m);sheet(pack)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--slug');p.add_argument('--source');p.add_argument('--prompt-file');p.add_argument('--import-characters',action='store_true');a=p.parse_args()
    if a.slug:extract(a.slug,a.source,Path(a.prompt_file).read_text(encoding='utf8'))
    if a.import_characters:import_characters()
    validate()
