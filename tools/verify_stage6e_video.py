"""Normalize an existing review MP4 if needed, fully decode and extract review frames."""
import json
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]

def inspect(path):
    return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-show_chapters','-of','json',str(path)],text=True))
def run():
    folder=ROOT/'docs/previews/stage6e';output=folder/'Brother-Eye-Stage-6E.mp4'
    details=inspect(output);video=next(s for s in details['streams'] if s['codec_type']=='video')
    original_duration=float(details['format']['duration'])
    if video['pix_fmt']=='yuvj420p':
        with tempfile.TemporaryDirectory(prefix='brother-eye-mp4-color-') as d:
            corrected=Path(d)/'review.mp4'
            command=['ffmpeg','-y','-hide_banner','-loglevel','warning','-i',str(output),'-map','0:v:0','-map_metadata','0','-map_chapters','0','-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_trc','bt709','-color_primaries','bt709','-c:d','copy','-movflags','+faststart',str(corrected)]
            result=subprocess.run(command,capture_output=True,text=True,timeout=180)
            (folder/'color-normalization.log').write_text(result.stderr);assert result.returncode==0,result.stderr
            assert abs(float(inspect(corrected)['format']['duration'])-original_duration)<.05
            output.write_bytes(corrected.read_bytes())
    details=inspect(output);video=next(s for s in details['streams'] if s['codec_type']=='video')
    assert video['codec_name']=='h264' and video['pix_fmt']=='yuv420p'
    assert (video['width'],video['height'])==(1440,900) and video['r_frame_rate']=='24/1'
    result=subprocess.run(['ffmpeg','-v','error','-i',str(output),'-f','null','-'],capture_output=True,text=True,timeout=180)
    assert result.returncode==0 and not result.stderr,result.stderr
    for seconds in (2,9,16,29,39,47,55):
        if seconds<original_duration:
            subprocess.run(['ffmpeg','-y','-v','error','-ss',str(seconds),'-i',str(output),'-frames:v','1',str(folder/f'video-{seconds:02d}s.jpg')],check=True,timeout=30)
    details['verification']={'full_decode':'passed','width':1440,'height':900,'fps':24,'silent':not any(s['codec_type']=='audio' for s in details['streams']),'scope':'Existing live review recording normalized to standard limited-range H.264; duration and chapter markers preserved. Raw capture frames were temporary; performance is measured separately.'}
    (folder/'video-verification.json').write_text(json.dumps(details,indent=2)+'\n')
    print(f'PASS MP4 fully decoded: {original_duration:.2f}s, H.264 yuv420p, 1440x900, 24 fps; {output}')
if __name__=='__main__':run()
