"""Read-only PCM/provenance validation; never plays sounds or mutates user settings."""
from pathlib import Path
import argparse,array,hashlib,json,math,os,wave
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work-dir',type=Path,default=ROOT/'artifacts/signature-audio')
    ap.add_argument('--cache-dir',type=Path,default=Path(os.environ.get('LOCALAPPDATA',Path.home()/'.local/share'))/'CodeManager/SignatureAudio')
    ap.add_argument('--catalog',type=Path,default=ROOT/'skins/signature-audio/catalog.json')
    ap.add_argument('--cache-only',action='store_true',help='Validate installed PCM and provenance receipts without requiring original download artifacts')
    args=ap.parse_args();catalog=json.loads(args.catalog.read_text(encoding='utf-8-sig'));results=[];hashes=set()
    for s in catalog['sounds']:
        if s['status']!='verified':
            results.append(dict(slug=s['slug'],status='missing',reason=s['missing_reason']));continue
        folder=args.work_dir/s['slug'];p=folder/'signature.wav';installed=args.cache_dir/s['slug']/'signature.wav'
        source=folder/('source'+s['source_extension'])
        bundled=ROOT/s['bundled_file'] if s.get('bundled_file') else None
        if bundled:assert s.get('license')=='CC0-1.0' and sha(bundled)==s['output_sha256'],s['slug']+' bundled checksum mismatch'
        if args.cache_only:p=installed
        elif bundled:
            p=bundled
            assert s.get('license')=='CC0-1.0' and sha(bundled)==s['output_sha256'],s['slug']+' bundled checksum mismatch'
        else:assert sha(source)==s['source_sha256'],s['slug']+' source mismatch'
        with wave.open(str(p),'rb') as w:
            assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(2,2,44100)
            seconds=w.getnframes()/w.getframerate();samples=array.array('h',w.readframes(w.getnframes()))
        peak=max(map(abs,samples))/32768;rms=math.sqrt(sum(v*v for v in samples)/len(samples))/32768
        digest=sha(p);assert digest==s['output_sha256'],s['slug']+' output manifest mismatch'
        assert digest not in hashes;hashes.add(digest)
        assert 0<seconds<=3.0001 and 0<rms and peak<=.991
        assert not any(v in (-32768,32767) for v in samples),'clipped samples'
        assert sha(installed)==digest,'installed cache mismatch'
        receipt=json.loads((installed.parent/'signature.source.json').read_text(encoding='utf-8'))
        assert receipt['source_sha256']==s['source_sha256'] and receipt['actual_output']['sha256']==digest
        first=max(map(abs,samples[:2]))/32768;last=max(map(abs,samples[-2:]))/32768
        assert first<.03 and last<.03,'abrupt crop boundary'
        results.append(dict(slug=s['slug'],status='passed',seconds=seconds,peak=peak,rms=rms,first_frame_peak=first,last_frame_peak=last,sha256=digest,bytes=p.stat().st_size,installed=str(installed),source_file_checked=not args.cache_only and bundled is None,bundled_file_checked=bundled is not None,source_kind=s['source_kind'],verification=s['verification']))
    report=dict(verified_count=len(hashes),missing_count=sum(r['status']=='missing' for r in results),cache_only=args.cache_only,results=results)
    args.work_dir.mkdir(parents=True,exist_ok=True)
    (args.work_dir/('cache-validation.json' if args.cache_only else 'validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=True))
if __name__=='__main__':main()
