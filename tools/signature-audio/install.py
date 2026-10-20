"""Install sourced game signature clips locally; never synthesizes or plays audio.
Third-party source/processed audio stays in artifacts and the local user cache.
"""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, urllib.request, wave, array
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parents[2]

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def executable(explicit):
    if explicit:return explicit
    found=shutil.which('ffmpeg')
    if found:return found
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        raise SystemExit('FFmpeg not found. Pass --ffmpeg /path/to/ffmpeg. No dependency was installed.')

def check_wave(path):
    with wave.open(str(path),'rb') as w:
        if (w.getnchannels(),w.getsampwidth(),w.getframerate())!=(2,2,44100):raise ValueError('Expected stereo PCM16 44.1 kHz')
        seconds=w.getnframes()/w.getframerate()
        if not 0.01<=seconds<=3.0001:raise ValueError('Expected a signature of at most 3 seconds')
        pcm=array.array('h',w.readframes(w.getnframes()))
        peak=max(abs(v) for v in pcm)/32768
        if peak>.991:raise ValueError('Output peak exceeds the source-preserving ceiling')
        return {'seconds':seconds,'peak':peak,'sha256':digest(path),'bytes':path.stat().st_size}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--ffmpeg');ap.add_argument('--slug',action='append')
    ap.add_argument('--catalog',type=Path,default=ROOT/'skins/signature-audio/catalog.json')
    ap.add_argument('--work-dir',type=Path,default=ROOT/'artifacts/signature-audio')
    ap.add_argument('--cache-dir',type=Path,default=Path(os.environ.get('LOCALAPPDATA',Path.home()/'.local/share'))/'CodeManager/SignatureAudio')
    ap.add_argument('--replace',action='store_true',help='Explicitly replace an existing differing signature; custom WAV overrides in Audio/ are never touched')
    args=ap.parse_args();ffmpeg=args.ffmpeg
    catalog=json.loads(args.catalog.read_text(encoding='utf-8-sig'));reports=[]
    known={s['slug'] for s in catalog['sounds']}
    if args.slug and set(args.slug)-known:ap.error('Unknown signature slug: '+', '.join(sorted(set(args.slug)-known)))
    for sound in catalog['sounds']:
        slug=sound['slug']
        if args.slug and slug not in args.slug:continue
        if sound['status']!='verified':
            reports.append({'slug':slug,'status':'missing','reason':sound['missing_reason']});continue
        try:
            reports.append(install_one(sound,args,ffmpeg))
        except (OSError,ValueError,KeyError,subprocess.SubprocessError,wave.Error) as error:
            reports.append({'slug':slug,'status':'failed','error':str(error),'source_url':sound.get('source_url')})
    args.work_dir.mkdir(parents=True,exist_ok=True)
    (args.work_dir/'install-report.json').write_text(json.dumps({'updated_at':datetime.now(timezone.utc).isoformat(),'results':reports},indent=2)+'\n',encoding='utf-8')
    for result in reports:print(json.dumps(result,ensure_ascii=True))
    if any(r['status']=='failed' for r in reports):raise SystemExit(1)

def install_one(sound,args,ffmpeg):
    slug=sound['slug']
    if not slug or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in slug):raise ValueError('Unsafe catalog slug')
    if sound['source_extension'] not in ('.mp3','.ogg','.wav'):raise ValueError('Unexpected source format')
    destination=args.cache_dir/slug/'signature.wav'
    # Existing local audio is immediately usable even when its original host is
    # offline. Ordinary installation must not require another download/decoder
    # just to preserve a file the user already has.
    if destination.exists() and not args.replace:
        return {'slug':slug,'status':'preserved-existing','path':str(destination),'sha256':digest(destination)}
    ffmpeg=executable(ffmpeg)
    folder=args.work_dir/slug;folder.mkdir(parents=True,exist_ok=True)
    source=folder/('source'+sound['source_extension'])
    if not source.exists() or digest(source)!=sound['source_sha256']:
        request=urllib.request.Request(sound['source_url'],headers={'User-Agent':'OmniVibe-SignatureAudio/1.0'})
        with urllib.request.urlopen(request,timeout=30) as response:data=response.read(2_000_001)
        if len(data)>2_000_000:raise ValueError('Signature source exceeds the 2 MB download bound')
        if hashlib.sha256(data).hexdigest()!=sound['source_sha256']:raise ValueError('Source checksum changed for '+slug)
        source.write_bytes(data)
    output=folder/'signature.wav'
    command=[ffmpeg,'-y','-v','error','-ss',str(sound['trim_start_seconds']),'-i',str(source),
             '-t',str(sound['trim_duration_seconds']),'-map_metadata','-1','-ac','2','-ar','44100',
             '-af',sound['ffmpeg_filter'],'-fflags','+bitexact','-flags:a','+bitexact','-c:a','pcm_s16le',str(output)]
    subprocess.run(command,check=True,capture_output=True,timeout=30)
    metadata=check_wave(output)
    destination.parent.mkdir(parents=True,exist_ok=True)
    temporary=destination.with_suffix('.wav.tmp');shutil.copyfile(output,temporary);os.replace(temporary,destination)
    receipt={**sound,'installed_at_utc':datetime.now(timezone.utc).isoformat(),
             'path':str(destination),'actual_output':metadata,'conversion_command':command}
    (destination.parent/'signature.source.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return {'slug':slug,'status':'installed','path':str(destination),**metadata}

if __name__=='__main__':main()
