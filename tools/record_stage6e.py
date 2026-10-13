"""Record a live disposable 100-person review and encode an MP4 with chapter markers."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from check_stage6e import ROOT,fixture

def run():
    evidence=ROOT/'docs/previews/stage6e';evidence.mkdir(parents=True,exist_ok=True)
    output=evidence/'Brother-Eye-Stage-6E.mp4'
    for tool in ('ffmpeg','ffprobe'):
        if not shutil.which(tool):raise RuntimeError(f'{tool} is required to encode/verify the MP4.')
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage6e-video-') as d:
        folder=Path(d);db=folder/'world.sqlite3';frames=folder/'frames';frames.mkdir();target,seat=fixture(db,2)
        result=subprocess.run(['godot','--path',str(ROOT/'godot'),'--script','res://scripts/stage6e_video.gd','--','--with-simulation',f'--world-db={db}',f'--frames-dir={frames}',f'--target-id={target}',f'--seat-id={seat}'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
        (evidence/'video.log').write_text(result.stdout);print(result.stdout,flush=True)
        assert result.returncode==0 and 'failures=0' in result.stdout and 'ERROR:' not in result.stdout
        deadline=time.monotonic()+10
        while list(folder.glob('session-*.json')) and time.monotonic()<deadline:time.sleep(.05)
        assert not list(folder.glob('session-*.json')),'owned review backend failed to stop'
        manifest=json.loads((frames/'frames.json').read_text());images=manifest['frames']
        (evidence/'video-capture.json').write_text(json.dumps(manifest,indent=2)+'\n')
        capture_duration=images[-1]['time']-images[0]['time'] if len(images)>1 else 0
        assert capture_duration>40 and len(images)/capture_duration>15, 'Capture rate too low; existing MP4 preserved. See video-capture.json and rerun while the Mac is idle.'
        concat=frames/'capture.ffconcat';lines=['ffconcat version 1.0']
        for index,frame in enumerate(images):
            duration=images[index+1]['time']-frame['time'] if index+1<len(images) else 1/24
            assert duration>0
            lines.extend([f"file '{frame['name']}'",f'duration {duration:.9f}'])
        lines.append(f"file '{images[-1]['name']}'");concat.write_text('\n'.join(lines)+'\n')
        duration=images[-1]['time']-images[0]['time']+1/24
        chapters=folder/'chapters.txt';lines=[';FFMETADATA1']
        for i,chapter in enumerate(manifest['chapters']):
            start=max(0,chapter['elapsed_seconds']-images[0]['time'])
            end=max(start+.001,manifest['chapters'][i+1]['elapsed_seconds']-images[0]['time']) if i+1<len(manifest['chapters']) else duration
            lines.extend(['[CHAPTER]','TIMEBASE=1/1000',f'START={int(start*1000)}',f'END={int(end*1000)}',f"title={chapter['title']}"])
        chapters.write_text('\n'.join(lines)+'\n')
        command=['ffmpeg','-y','-hide_banner','-loglevel','warning','-f','concat','-safe','0','-i',str(concat),'-i',str(chapters),'-map_metadata','1','-map_chapters','1','-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p,fps=24','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_trc','bt709','-color_primaries','bt709','-movflags','+faststart','-an',str(output)]
        result=subprocess.run(command,text=True,capture_output=True,timeout=180)
        (evidence/'encode.log').write_text(result.stderr);assert result.returncode==0,result.stderr
        details=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-show_chapters','-of','json',str(output)],text=True))
        video=next(s for s in details['streams'] if s['codec_type']=='video')
        assert video['codec_name']=='h264' and video['pix_fmt']=='yuv420p' and (video['width'],video['height'])==(1440,900)
        assert abs(float(details['format']['duration'])-duration)<.25
        # Decode the whole deliverable to catch corrupt/truncated frames.
        decoded=subprocess.run(['ffmpeg','-v','error','-i',str(output),'-f','null','-'],capture_output=True,text=True,timeout=180)
        assert decoded.returncode==0 and not decoded.stderr,decoded.stderr
        for seconds in (2,9,16,29,39,47,55):
            if seconds<duration:
                subprocess.run(['ffmpeg','-y','-v','error','-ss',str(seconds),'-i',str(output),'-frames:v','1',str(evidence/f'video-{seconds:02d}s.jpg')],check=True,timeout=30)
        details['capture']={k:v for k,v in manifest.items() if k!='frames'}
        details['capture'].update(captured_frames=len(images),first_frame_seconds=images[0]['time'],last_frame_seconds=images[-1]['time'])
        (evidence/'video-verification.json').write_text(json.dumps(details,indent=2)+'\n')
        print(f'PASS verified MP4: {duration:.2f}s, 1440x900 H.264, 24 fps, fully decoded; {output}',flush=True)
if __name__=='__main__':run()
