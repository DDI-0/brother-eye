"""Offline 24-hour lighting MP4. Does not open any world save or backend."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'docs/previews/day-cycle'

def encode(source):
    capture=json.loads((EVIDENCE/'capture.json').read_text())
    assert capture['day_frames']==1440 and capture['fps']==24
    samples=capture['samples']
    assert len(samples)==9 and samples[0]['hour']==samples[-1]['hour']==6
    assert max(s['energy'] for s in samples)>1.5 and min(s['energy'] for s in samples)<.15
    assert abs(samples[0]['energy']-samples[-1]['energy'])<1e-6
    output=EVIDENCE/'Brother-Eye-24-Hour-Cycle.mp4'
    count=capture['day_frames']+1
    source_info=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=nb_frames','-of','json',str(source)],text=True))
    # MovieWriter adds one closing duplicate after the final post-draw capture.
    # Exclude that duplicate and the initialization frames, retaining 06:00→06:00.
    first=int(source_info['streams'][0]['nb_frames'])-count-1
    assert first>=0
    with tempfile.TemporaryDirectory(prefix='brother-eye-day-encode-') as d:
        metadata=Path(d)/'chapters.txt';lines=[';FFMETADATA1','title=Brother Eye - 24-hour lighting review']
        for i in range(8):
            h=(6+i*3)%24
            lines.extend(['[CHAPTER]','TIMEBASE=1/1000',f'START={i*7500}',f'END={(i+1)*7500}',f'title={h:02d}:00'])
        metadata.write_text('\n'.join(lines)+'\n')
        filters=f'trim=start_frame={first}:end_frame={first+count},setpts=PTS-STARTPTS,scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p,fps=24'
        result=subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','warning','-i',str(source),'-i',str(metadata),'-map','0:v:0','-map_metadata','1','-map_chapters','1','-vf',filters,'-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_trc','bt709','-color_primaries','bt709','-movflags','+faststart','-an',str(output)],capture_output=True,text=True,timeout=180)
        (EVIDENCE/'encode.log').write_text(result.stderr);assert result.returncode==0,result.stderr
    details=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-show_chapters','-of','json',str(output)],text=True))
    stream=next(s for s in details['streams'] if s['codec_type']=='video')
    assert stream['codec_name']=='h264' and stream['pix_fmt']=='yuv420p'
    assert (stream['width'],stream['height'])==(1440,900)
    assert abs(float(details['format']['duration'])-count/24)<.15
    result=subprocess.run(['ffmpeg','-v','error','-i',str(output),'-f','null','-'],capture_output=True,text=True,timeout=180)
    assert result.returncode==0 and not result.stderr,result.stderr
    for label,seconds in [('morning',.2),('noon',15),('sunset',30),('midnight',45),('next-morning',59.9)]:
        subprocess.run(['ffmpeg','-y','-v','error','-ss',str(seconds),'-i',str(output),'-frames:v','1',str(EVIDENCE/f'video-{label}.jpg')],check=True,timeout=30)
    details['verification']={'decode':'passed','cycle_samples':'passed','scope':capture['scope']}
    (EVIDENCE/'verification.json').write_text(json.dumps(details,indent=2)+'\n')
    print(f'PASS 24-hour lighting MP4: {details["format"]["duration"]}s, 1440x900, H.264, full decode and cycle endpoints verified; {output}')

def run(source=None):
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    if source:
        encode(source);return
    with tempfile.TemporaryDirectory(prefix='brother-eye-day-movie-') as d:
        movie=Path(d)/'day.avi'
        result=subprocess.run(['godot','--path',str(ROOT/'godot'),'--script','res://scripts/day_cycle_review.gd','--write-movie',str(movie),'--fixed-fps','24','--disable-vsync','--','--no-simulation',f'--evidence-dir={EVIDENCE}'],capture_output=True,text=True,timeout=300)
        (EVIDENCE/'render.log').write_text(result.stdout+result.stderr)
        assert result.returncode==0 and 'DAY_CYCLE_VIDEO failures=0' in result.stdout and 'ERROR:' not in result.stdout+result.stderr
        encode(movie)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--encode-existing',type=Path);args=parser.parse_args();run(args.encode_existing)
