"""Retiming only: preserve every compressed GIF image byte and all 96 frames.

Border light is decorative. 150 ms cadence reduces full-background decoding and
repainting by one third; source geometry, resolution, artwork and motion path stay.
"""
from pathlib import Path
from io import BytesIO
import hashlib,json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1];ASSETS=ROOT/'themes/windows-terminal/assets/refined-v1'
def timings(data):
 if data[:6] not in (b'GIF87a',b'GIF89a'):raise ValueError('Not GIF')
 position=13+(3*(1<<((data[10]&7)+1)) if data[10]&128 else 0);offsets=[]
 while position<len(data):
  tag=data[position];position+=1
  if tag==0x3b:break
  if tag==0x21:
   label=data[position];position+=1
   if label==0xf9:
    if data[position]!=4:raise ValueError('Invalid graphic control extension')
    offsets.append(position+2);position+=6;continue
  elif tag==0x2c:
   flags=data[position+8];position+=9
   if flags&128:position+=3*(1<<((flags&7)+1))
   position+=1
  else:raise ValueError('Invalid GIF block')
  while True:
   size=data[position];position+=1
   if size==0:break
   position+=size
 return offsets
def main():
 rows=[];updates={}
 for path in sorted(ASSETS.glob('*.gif')):
  before=path.read_bytes();after=bytearray(before);offsets=timings(before)
  assert len(offsets)==96,path
  normalized_before=bytearray(before);normalized_after=bytearray(after)
  for offset in offsets:
   assert int.from_bytes(before[offset:offset+2],'little') in (10,15)
   after[offset:offset+2]=(15).to_bytes(2,'little')
   normalized_before[offset:offset+2]=b'\0\0'
  normalized_after=bytearray(after)
  for offset in offsets:normalized_after[offset:offset+2]=b'\0\0'
  assert normalized_before==normalized_after,'Non-timing GIF bytes changed'
  a,b=Image.open(BytesIO(before)),Image.open(BytesIO(after));assert a.size==b.size==(1280,754) and a.n_frames==b.n_frames==96
  for frame in [0,24,48,72,95]:
   a.seek(frame);b.seek(frame);assert a.convert('RGB').tobytes()==b.convert('RGB').tobytes()
  path.write_bytes(after);sha=hashlib.sha256(after).hexdigest();updates[path.relative_to(ROOT).as_posix()]=sha
  rows.append(dict(file=path.relative_to(ROOT).as_posix(),frames=96,durationMs=150,framesPerSecond=1000/150,allCompressedImagesUnchanged=True,decodedCheckpoints=5,sha256=sha,bytes=len(after)))
 assert len(rows)==26,'Expected full and frame-only variants for 13 themes'
 def update(value):
  if isinstance(value,dict):
   file=value.get('file','').replace('\\','/')
   if file in updates:value['sha256']=updates[file];value['durationMs']=150
   for item in value.values():update(item)
  elif isinstance(value,list):
   for item in value:update(item)
 for path in ASSETS.glob('*.json'):
  value=json.loads(path.read_text(encoding='utf-8-sig'));update(value);path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 output=ROOT/'artifacts/performance';output.mkdir(parents=True,exist_ok=True)
 (output/'terminal-animation.json').write_text(json.dumps(dict(passed=True,variants=rows,changed='GIF display delays only: 100 ms to 150 ms; 9.6 s loop to 14.4 s',renderWakeupReduction=1/3),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('26 GIFs retimed; all compressed frame payloads, resolution and loop frames preserved.')
if __name__=='__main__':main()
