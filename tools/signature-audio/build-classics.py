"""Build the three bundled classic signatures from pinned CC0 acoustic samples.

No synthesized tones or legacy UI beeps. Only trim, constant gain and edge fades.
Source recordings remain in ignored artifacts; small licensed derivatives ship.
"""
from pathlib import Path
import array, hashlib, importlib.util, json, math, shutil, subprocess, urllib.request

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'artifacts/classic-signatures'
COMMIT='c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e'
BASE='https://raw.githubusercontent.com/sgossner/VCSL/'+COMMIT+'/'
SPECS=[
 ('ink-jade','玉铃清鸣','Bell Tree/Individual/BellTree_Hit_E5_rr1_Mid.wav','71aeec32c08bc636c16f1271d52fc56ba14ff6e163f014b53538c87deb02e282',1.05,.18,'清亮单击，配合玉石与青铜机关；真实铃树采样，不冒称玉石实录。'),
 ('midnight','星钟微光','Glockenspiel/glock_medium_C6_01.wav','e942cbf502cf6731df2925945fe3234c876cb63f047d91007b6929887f9e4904',1.45,.28,'高音钟琴的清透泛音，配合青金星轨与月色。'),
 ('cinnabar','铜钟落印','Tubular Bells 1/chimes_C3_f_rr1.wav','76d51955e61e70e7a6b46a05865cd0f06f4948aaab97b1925f0f06f193f717f5',1.25,.25,'低音管钟的厚重击发与短尾，配合漆红剑匣与铜金边饰。')
]

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def download(url,path,expected=None):
    if path.exists() and (expected is None or sha(path)==expected): return
    request=urllib.request.Request(url,headers={'User-Agent':'OmniVibe-ClassicAudio/1.0'})
    with urllib.request.urlopen(request,timeout=30) as response: data=response.read(8_000_001)
    if len(data)>8_000_000: raise ValueError('Source exceeds download bound')
    if expected and hashlib.sha256(data).hexdigest()!=expected: raise ValueError('Pinned source checksum mismatch')
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)

def main():
    from urllib.parse import quote
    spec=importlib.util.spec_from_file_location('signature_installer',Path(__file__).with_name('install.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    ffmpeg=module.executable(None);entries=[]
    for slug,name,relative,expected,duration,fade,design in SPECS:
        source_path='Idiophones/Struck Idiophones/'+relative
        source_url=BASE+quote(source_path)
        folder=WORK/slug;folder.mkdir(parents=True,exist_ok=True)
        source=folder/'source.wav';download(source_url,source,expected)
        decoded=array.array('f',subprocess.check_output([ffmpeg,'-v','error','-i',str(source),'-ac','2','-ar','44100','-f','f32le','-']))
        peak=max(map(abs,decoded));threshold=max(.0003,peak*.004)
        first=next(i//2 for i,v in enumerate(decoded) if abs(v)>=threshold)
        start=max(0,(first-88)/44100)
        segment=decoded[int(start*44100)*2:int((start+duration)*44100)*2]
        # A gentle fixed level for frequent switching; leave transients intact.
        gain=min(.64/max(map(abs,segment)),.105/math.sqrt(sum(v*v for v in segment)/len(segment)))
        filters=f'volume={gain:.12f},afade=t=in:st=0:d=0.001,afade=t=out:st={duration-fade:.9f}:d={fade}'
        output=ROOT/'skins/signature-audio/bundled'/slug/'signature.wav';output.parent.mkdir(parents=True,exist_ok=True)
        command=[ffmpeg,'-y','-v','error','-ss',f'{start:.9f}','-i',str(source),'-t',str(duration),'-map_metadata','-1','-ac','2','-ar','44100','-af',filters,'-fflags','+bitexact','-flags:a','+bitexact','-c:a','pcm_s16le',str(output)]
        subprocess.run(command,check=True,capture_output=True,timeout=30)
        metadata=module.check_wave(output)
        entries.append(dict(slug=slug,name=name,game='OmniVibe original classic theme',status='verified',source_page='https://github.com/sgossner/VCSL',source_url=source_url,source_extension='.wav',source_sha256=expected,source_bytes=source.stat().st_size,source_kind='cc0-acoustic-theme-adaptation',rights_holder='Versilian Studios LLC / Sam Gossner',license='CC0-1.0',license_url=BASE+'LICENSE',license_note='CC0 acoustic sample; derivative WAV is distributable and bundled. No game audio or synthetic legacy cue.',verification='Pinned upstream Git commit and SHA-256; original CC0 instrument recording, trimmed with constant gain and smooth edge fades.',design=design,trim_start_seconds=start,trim_duration_seconds=duration,ffmpeg_filter=filters,conversion_format='PCM signed 16-bit stereo 44100 Hz',processing_note='No resynthesis, pitch change, compression, layering or looping. Short original acoustic strike, constant gain, 1 ms onset fade and smooth tail.',output_sha256=metadata['sha256'],output_seconds=metadata['seconds'],output_peak=metadata['peak'],bundled_file=output.relative_to(ROOT).as_posix(),verified_at='2026-10-20'))
        print(slug,metadata)
    license_file=WORK/'VCSL-CC0.txt';download(BASE+'LICENSE',license_file)
    shutil.copyfile(license_file,ROOT/'skins/signature-audio/bundled/VCSL-CC0.txt')
    catalog_path=ROOT/'skins/signature-audio/catalog.json';catalog=json.loads(catalog_path.read_text(encoding='utf-8-sig'))
    catalog['policy']='One signature per theme: ten locally installed sourced game clips, three bundled CC0 acoustic classic adaptations. Missing game clips stay silent; no legacy synthetic substitution.'
    slugs={e['slug'] for e in entries};catalog['sounds']=[s for s in catalog['sounds'] if s['slug'] not in slugs]+entries
    catalog_path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (WORK/'build-report.json').write_text(json.dumps(dict(passed=True,source_commit=COMMIT,results=entries),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__': main()
