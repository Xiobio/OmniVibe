"""Build short CC0 acoustic completion cues; no synthetic tones or game assets."""
from pathlib import Path
from urllib.parse import quote
import array,hashlib,importlib.util,json,math,subprocess,urllib.request
ROOT=Path(__file__).resolve().parents[2];WORK=ROOT/'artifacts/completion-audio';COMMIT='c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e'
BASE='https://raw.githubusercontent.com/sgossner/VCSL/'+COMMIT+'/'
SPECS=[
 ('ink-jade','玉铃回响','Struck Idiophones/Bell Tree/Individual/BellTree_Hit_D5_rr1_Mid.wav',.52),
 ('midnight','青金星铃','Struck Idiophones/Glockenspiel/glock_medium_C6_01.wav',.55),
 ('cinnabar','铜印轻落','Struck Idiophones/Tubular Bells 1/chimes_C3_f_rr1.wav',.5),
 ('hextech','棱晶轻鸣','Struck Idiophones/Glockenspiel/glock_medium_C5_01.wav',.5),
 ('tactical','战术扣响','Struck Idiophones/Woodblock/wood_click2_mp.wav',.32),
 ('protocol','协议确认','Struck Idiophones/Woodblock/wood_click_mp.wav',.34),
 ('adventure','装备归位','Plucked Idiophones/Kalimba, Kenya/Mbira6_Normal_MainSpirit_A4_k1_vl3_rr2.wav',.48),
 ('arsenal','兵匣铃响','Struck Idiophones/Bell Tree/Individual/BellTree_Hit_C5_rr1_Mid.wav',.48),
 ('relic','灵蕴微鸣','Plucked Idiophones/Kalimba, Kenya/Mbira6_Normal_MainSpirit_B3_k3_vl3_rr2.wav',.5),
 ('starlight','星曜落定','Struck Idiophones/Glockenspiel/glock_medium_C7_01.wav',.48),
 ('formation','棋子落位','Struck Idiophones/Woodblock/wood_click3_vl1.wav',.32),
 ('astral','星旅铃声','Struck Idiophones/Bell Tree/Individual/BellTree_Hit_F#5_rr1_Mid.wav',.55),
 ('wonderland','云铃回音','Struck Idiophones/Bell Tree/Individual/BellTree_Hit_A#5_rr1_Mid.wav',.55)]
def main():
 WORK.mkdir(parents=True,exist_ok=True);out=ROOT/'skins/completion-audio';out.mkdir(parents=True,exist_ok=True)
 spec=importlib.util.spec_from_file_location('installer',Path(__file__).with_name('install.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);ffmpeg=module.executable(None)
 tree_file=WORK/'vcsl-tree.json'
 if not tree_file.exists():
  request=urllib.request.Request('https://api.github.com/repos/sgossner/VCSL/git/trees/'+COMMIT+'?recursive=1',headers={'User-Agent':'OmniVibe-CompletionAudio'})
  with urllib.request.urlopen(request,timeout=25) as r:tree_file.write_bytes(r.read(8_000_000))
 tree=json.loads(tree_file.read_text(encoding='utf-8'));assert tree['sha']==COMMIT and not tree.get('truncated');blobs={x['path']:x['sha'] for x in tree['tree'] if x['type']=='blob'};entries=[]
 for slug,name,relative,duration in SPECS:
  path='Idiophones/'+relative;url=BASE+quote(path);source=WORK/'sources'/slug/'source.wav';source.parent.mkdir(parents=True,exist_ok=True)
  if not source.exists():
   with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'OmniVibe-CompletionAudio'}),timeout=25) as r:data=r.read(8_000_001)
   if len(data)>8_000_000:raise ValueError('Source too large')
   source.write_bytes(data)
  data=source.read_bytes();assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==blobs[path],path
  pcm=array.array('f',subprocess.check_output([ffmpeg,'-v','error','-i',str(source),'-ac','2','-ar','44100','-f','f32le','-']))
  peak=max(map(abs,pcm));threshold=max(.0003,peak*.005);first=next(i//2 for i,v in enumerate(pcm) if abs(v)>=threshold);start=max(0,(first-88)/44100)
  segment=pcm[int(start*44100)*2:int((start+duration)*44100)*2];rms=math.sqrt(sum(v*v for v in segment)/len(segment));gain=min(.48/max(map(abs,segment)),.075/rms)
  fade=min(.16,duration*.35);filters=f'volume={gain:.12f},afade=t=in:d=0.002,afade=t=out:st={duration-fade:.9f}:d={fade:.9f}'
  target=out/slug/'complete.wav';target.parent.mkdir(parents=True,exist_ok=True)
  subprocess.run([ffmpeg,'-y','-v','error','-ss',f'{start:.9f}','-i',str(source),'-t',str(duration),'-ac','2','-ar','44100','-map_metadata','-1','-af',filters,'-fflags','+bitexact','-flags:a','+bitexact','-c:a','pcm_s16le',str(target)],check=True,capture_output=True)
  metadata=module.check_wave(target)
  entries.append(dict(slug=slug,name=name,source_url=url,source_commit=COMMIT,source_git_blob=blobs[path],source_sha256=hashlib.sha256(data).hexdigest(),license='CC0-1.0',source_author='Versilian Studios LLC / Sam Gossner',start_seconds=start,gain=gain,fade_seconds=fade,output_file=target.relative_to(ROOT).as_posix(),**metadata))
  print(slug,round(metadata['seconds'],3),flush=True)
 (out/'catalog.json').write_text(json.dumps(dict(version=1,policy='Short acoustic theme adaptations, separately composed from the existing switch signatures. No synthesis, pitch shifts, compression, layering or looping. Completion player applies half the shared volume.',sounds=entries),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
