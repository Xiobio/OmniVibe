"""Original procedural Foley and musical UI design. No extracted game samples.
Run: python tools/game-audio/generate.py --validate
"""
from pathlib import Path
import argparse, hashlib, json, math, wave
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'skins' / 'audio'
RATE = 44100
CUES = ['switch', 'capture', 'remove', 'expand', 'collapse', 'inventoryopen', 'inventoryclose',
        'arrange', 'restore', 'reorder', 'waiting', 'ready', 'error', 'detent']
THEMES = {
    'ink-jade': ('Jade mechanism', 'bamboo, jade bead and brushed silk', 0),
    'midnight': ('Midnight mountain', 'low glass, airy wind and distant bronze', 1),
    'cinnabar': ('Cinnabar forge', 'dry wood, bronze latch and ember', 2),
    'hextech': ('Hex crystal engine', 'geared brass ratchet and resonant crystal charge', 3),
    'tactical': ('Tactical equipment', 'receiver slide, spring latch and damp radio pulse', 4),
    'protocol': ('Protocol interface', 'digital packet, filtered glitch and clean relay', 5),
    'adventure': ('Adventure equipment', 'leather rustle, forged clasp and inventory coin', 6),
    'arsenal': ('Naraka-inspired arsenal', 'drawn blade, displaced air and jade scabbard latch', 7),
    'relic': ('Wukong-inspired relic', 'stone resonance, woodblock and low ritual bronze', 8),
    'starlight': ('Royal skill light', 'golden ability burst and bright pentatonic glissando', 9),
    'formation': ('Formation board', 'wooden token landing and magical promotion arpeggio', 10),
    'astral': ('Astral journey', 'celestial glass, harp pluck and stardust', 11),
    'wonderland': ('Porcelain dream', 'bamboo flute breath, porcelain chime and painted wood', 12),
}

class Designer:
    def __init__(self, seed, duration):
        self.rng = np.random.default_rng(seed)
        self.x = np.zeros((int(duration * RATE), 2), dtype=np.float64)
    def add(self, a, at=0, gain=1, pan=0):
        start = int(at * RATE)
        if start >= len(self.x): return
        a = np.asarray(a)[:len(self.x) - start] * gain
        # Narrow panorama: useful on speakers and comfortable on headphones.
        self.x[start:start + len(a), 0] += a * math.sqrt((1 - pan) / 2)
        self.x[start:start + len(a), 1] += a * math.sqrt((1 + pan) / 2)
    def noise(self, duration, band=(180, 10000), decay=16):
        n = int(duration * RATE); t = np.arange(n) / RATE
        a = self.rng.normal(0, .3, n)
        a = sosfilt(butter(2, band, 'bandpass', fs=RATE, output='sos'), a)
        return a * (1 - np.exp(-t * 950)) * np.exp(-t * decay)
    def tone(self, f, duration=.2, decay=15, metal=False):
        t = np.arange(int(duration * RATE)) / RATE
        ratios = (1, 2.756, 5.404, 8.933) if metal else (1, 2, 3)
        a = sum(np.sin(2*np.pi*f*r*t) * np.exp(-t*decay*(1+i*.65)) / (1+i)**1.5
                for i, r in enumerate(ratios))
        return a * (1 - np.exp(-t * 1300))
    def sweep(self, f0, f1, duration=.12):
        t=np.arange(int(duration*RATE))/RATE
        phase=2*np.pi*(f0*t+(f1-f0)*t*t/(2*duration))
        return np.sin(phase)*np.sin(np.pi*t/duration)**1.5
    def echo(self):
        dry = self.x.copy()
        for delay, gain in [(0.027,.1),(.057,.065),(.091,.035)]:
            n=int(delay*RATE)
            self.x[n:] += dry[:-n, ::-1] * gain
    def finish(self, peak):
        self.echo()
        self.x -= np.mean(self.x, axis=0)
        n = len(self.x)
        edge = min(350, n//5)
        self.x[:edge] *= np.linspace(0,1,edge)[:,None]**1.4
        self.x[-edge:] *= np.linspace(1,0,edge)[:,None]**1.4
        window=np.ones(n)
        window[:edge]=np.linspace(0,1,edge)**1.4
        window[-edge:]=np.linspace(1,0,edge)**1.4
        self.x-=window[:,None]*(self.x.sum(axis=0)/window.sum())
        self.x *= peak / max(np.max(np.abs(self.x)), 1e-8)
        return np.round(self.x*32767).astype('<i2')

def motif(d, theme, cue, at=0, intensity=1):
    """Families differ in synthesis, timing, noise spectrum and physical material."""
    down = cue in ('remove','collapse','inventoryclose','restore','error')
    k = -.08 if down else .04
    if theme == 'tactical':
        for delay, gain in [(0,1),(.037,.63),(.084,.38)]:
            d.add(d.noise(.08,(280,7200),68),at+delay,.8*gain)
            d.add(d.tone(170+delay*1700,.09,55),at+delay,.18*gain)
        d.add(d.noise(.11,(1500,5200),38),at+.018,.28)
        if cue in ('capture','arrange','ready'): d.add(d.sweep(1020,960,.035),at+.14,.09)
    elif theme == 'protocol':
        for i, delay in enumerate([0,.019,.048]):
            d.add(d.sweep(1700-i*210,980+i*190,.018),at+delay,.22)
        d.add(d.noise(.04,(2200,8500),100),at+.012,.15)
        d.add(d.tone(370 if down else 740,.12,28),at+.054,.12)
    elif theme == 'arsenal':
        air=d.noise(.20,(700,9500),14)
        air*=np.sin(np.linspace(0,np.pi,len(air)))**1.6
        d.add(air,at,.8)
        d.add(d.tone(1540 if not down else 980,.3,18,True),at+.036,.14)
        d.add(d.noise(.042,(2600,13000),85),at+.075,.42)
        d.add(d.tone(205,.11,38),at+.08,.11)
    elif theme == 'hextech':
        for i in range(4): d.add(d.noise(.025,(1000,6000),120),at+i*.015,.28/(1+i*.2))
        d.add(d.tone(790*(1+k),.43,11,True),at+.032,.28)
        d.add(d.sweep(340,1400 if not down else 240,.15),at,.10)
        d.add(d.tone(1185,.36,15),at+.055,.1)
    elif theme == 'relic':
        d.add(d.tone(156,.49,8,True),at,.4)
        d.add(d.tone(403,.24,20,True),at+.023,.18)
        d.add(d.noise(.12,(70,1700),42),at,.40)
        d.add(d.tone(690,.23,24),at+.045,.08)
    elif theme == 'formation':
        d.add(d.noise(.07,(300,3400),65),at,.62)
        d.add(d.tone(340,.115,39),at,.30)
        d.add(d.tone(510,.12,32),at+.022,.10)
        if cue not in ('switch','detent'): d.add(d.tone(1174,.28,15,True),at+.065,.08)
    elif theme == 'adventure':
        d.add(d.noise(.18,(110,2600),21),at,.65)
        d.add(d.tone(245,.14,26,True),at+.04,.28)
        d.add(d.tone(1870,.27,17,True),at+.074,.11)
        d.add(d.noise(.025,(2500,11500),90),at+.06,.30)
    elif theme == 'astral':
        for i,(f,delay) in enumerate([(1046,0),(1568,.042),(2093,.083)]):
            d.add(d.tone(f*(.84 if down else 1),.48,10,True),at+delay,.20/(1+i*.3),(-.2 if i%2 else .2))
        d.add(d.noise(.24,(4500,15000),14),at,.14)
    elif theme == 'starlight':
        d.add(d.sweep(520,1250 if not down else 290,.105),at,.16)
        for i,f in enumerate([880,1108,1320]): d.add(d.tone(f,.38,12),at+i*.03,.19/(1+i*.3))
        d.add(d.noise(.09,(3000,12000),38),at+.01,.13)
    elif theme == 'wonderland':
        d.add(d.tone(1318,.34,13,True),at,.20)
        d.add(d.tone(659,.28,16),at+.025,.18)
        breath=d.noise(.15,(600,2400),12)
        d.add(breath,at,.20)
        d.add(d.tone(231,.065,52),at+.015,.22)
    elif theme == 'midnight':
        d.add(d.tone(294,.40,10,True),at,.24)
        d.add(d.tone(880,.34,12),at+.026,.13)
        d.add(d.noise(.2,(120,2700),14),at,.22)
    elif theme == 'cinnabar':
        d.add(d.tone(185,.15,27),at,.32)
        d.add(d.noise(.07,(350,5800),46),at,.58)
        d.add(d.tone(940,.3,15,True),at+.032,.18)
    else:
        d.add(d.tone(1648,.31,16,True),at,.23)
        d.add(d.tone(392,.095,37),at+.017,.25)
        d.add(d.noise(.10,(1400,9000),24),at,.24)

def design(theme, cue, index):
    duration = {'switch':.30,'capture':.48,'remove':.34,'expand':.34,'collapse':.28,
                'inventoryopen':.51,'inventoryclose':.33,'arrange':.56,'restore':.45,
                'reorder':.24,'waiting':.62,'ready':.75,'error':.60,'detent':.052}[cue]
    d=Designer(13017+index*997+CUES.index(cue)*83,duration)
    if cue=='detent':
        # Tiny dry material contact. Intentionally far quieter than a switch.
        f=[840,450,240,1120,190,1740,290,1860,150,1280,335,2050,670][index]
        d.add(d.noise(.04,(400,7000),115),gain=.4)
        d.add(d.tone(f,.047,95,metal=index in (0,3,7,8,11,12)),gain=.18)
        peak=.14
    elif cue in ('waiting','ready','error'):
        # Notifications have semantic contours independent of skin: question,
        # resolution, or restrained double caution. Theme's material stays audible.
        motif(d,theme,'reorder')
        base=[659,587,415,784,440,880,392,587,220,880,523,1046,659][index]
        notes={'waiting':[(1,.16),(.891,.32)],'ready':[(1,.14),(1.25,.26),(1.5,.38)],
               'error':[(.75,.12),(.667,.29)]}[cue]
        for ratio,at in notes:
            d.add(d.tone(base*ratio,.30,13,metal=index in(0,3,8,11,12)),at,.12)
        if cue=='error': d.add(d.noise(.13,(120,1300),23),.26,.22)
        peak=.40 if cue!='error' else .43
    else:
        motif(d,theme,cue)
        f=[784,588,466,1176,660,1320,523,880,330,1320,784,1568,988][index]
        if cue == 'capture':
            motif(d,theme,'reorder',.125)
            d.add(d.tone(f,.30,14,True),.17,.08)
        elif cue == 'inventoryopen':
            d.add(d.noise(.25,(400,5500),12),.025,.17)
            for i,r in enumerate((1,1.25,1.5)):
                d.add(d.tone(f*r,.25,17,True),.09+i*.046,.065,(-.22,0,.22)[i])
        elif cue == 'arrange':
            # Four corners settle into formation, rather than another capture.
            for i in range(4):
                d.add(d.noise(.028,(500,4500),95),.09+i*.057,.22,(-.35,.35,-.15,.15)[i])
                d.add(d.tone(f*(.5+i*.125),.12,24),.09+i*.057,.055)
            d.add(d.tone(f*1.5,.25,18,True),.32,.06)
        elif cue == 'restore':
            for i,r in enumerate((1,.75,.5)):
                d.add(d.tone(f*r,.15,22),.07+i*.06,.065)
        elif cue == 'expand':
            d.add(d.sweep(f*.45,f*.9,.12),.015,.055)
            d.add(d.noise(.19,(1400,7500),14),.025,.15)
        elif cue == 'collapse':
            d.add(d.sweep(f*.9,f*.4,.10),.025,.065)
            d.add(d.noise(.10,(100,2600),38),.08,.20)
        elif cue == 'inventoryclose':
            d.add(d.noise(.15,(180,3000),28),.035,.24)
            d.add(d.tone(f*.5,.13,30),.12,.085)
        elif cue == 'remove':
            d.add(d.noise(.10,(100,2600),38),.08,.20)
            d.add(d.sweep(f*.6,f*.3,.065),.09,.055)
        elif cue=='reorder': d.add(d.tone(180+index*17,.055,50),.065,.1)
        peak={'switch':.32,'capture':.38,'remove':.28,'expand':.25,'collapse':.22,
              'inventoryopen':.32,'inventoryclose':.25,'arrange':.36,'restore':.30,'reorder':.21}[cue]
    return d.finish(peak)

def metrics(pcm):
    x=pcm.astype(float)/32768
    return dict(peak=round(float(np.max(np.abs(x))),6),rms=round(float(np.sqrt(np.mean(x*x))),6),
                dc=round(float(np.max(np.abs(np.mean(x,axis=0)))),8),
                first_frame=pcm[0].tolist(),last_frame=pcm[-1].tolist(),
                max_step=round(float(np.max(np.abs(np.diff(x,axis=0)))),6),
                seconds=round(len(x)/RATE,4))

def main():
    argparse.ArgumentParser().add_argument('--validate',action='store_true')
    manifest=dict(version=1,sample_rate=RATE,channels=2,bits=16,
        license='CC0-1.0',provenance='Original procedural Foley and instrument synthesis; no extracted game audio, no official voices.',
        generator='tools/game-audio/generate.py',themes={})
    hashes=set(); results=[]
    for slug,(name,materials,index) in THEMES.items():
        folder=OUT/slug;folder.mkdir(parents=True,exist_ok=True)
        entries={}
        for cue in CUES:
            pcm=design(slug,cue,index); path=folder/(cue+'.wav')
            with wave.open(str(path),'wb') as w:
                w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())
            h=hashlib.sha256(path.read_bytes()).hexdigest();m=metrics(pcm)
            assert h not in hashes,(slug,cue,'duplicate');hashes.add(h)
            assert .005<m['rms']<.2 and m['peak']<.45 and m['dc']<.002,(slug,cue,m)
            assert m['first_frame']==[0,0] and m['last_frame']==[0,0]
            entries[cue]=dict(file=f'{slug}/{cue}.wav',sha256=h,**m)
            results.append(dict(theme=slug,cue=cue,**m))
        manifest['themes'][slug]=dict(name=name,materials=materials,cues=entries)
    OUT.mkdir(exist_ok=True)
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    report=ROOT/'artifacts'/'game-audio';report.mkdir(parents=True,exist_ok=True)
    (report/'waveform-validation.json').write_text(json.dumps(dict(passed=True,files=len(results),unique_hashes=len(hashes),results=results),indent=2)+'\n')
    # Audition playlist: switch/capture/ready per theme separated by actual silence.
    montage=[]
    for slug,(_,_,index) in THEMES.items():
        for cue in ('switch','capture','ready'):
            montage.extend([design(slug,cue,index),np.zeros((int(RATE*.23),2),dtype='<i2')])
    with wave.open(str(report/'all-themes-audition.wav'),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(np.concatenate(montage).tobytes())
    print(json.dumps(dict(files=len(results),unique=len(hashes),report=str(report/'waveform-validation.json'))))

if __name__=='__main__':main()
