"""Capture verified live policies and city tour, assemble the full MP4 showcase."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
from check_stage6e import fixture as city_fixture
EVIDENCE=ROOT/'docs/previews/showcase'
MODES=('arbiter','attendant','martyr','sovereign','city')

def fixture(path,mode):
    if mode=='city':return city_fixture(path,1)[1]
    store=Store(path);w=store.world;w.update(paused=True,time_scale=1)
    if mode=='arbiter':
        w['citizens'][30]['position']=[18,.12,-8]
        for index,severity in ((0,95),(1,85)):
            c=w['citizens'][index];p=[18+index*2,.12,-14]
            c['known_places']['park']['position']=p;c['goal'].update(place='park',position=p,reason='need')
            c.update(position=p,activity='socializing',navigation='ARRIVED');c['needs'].update(social=severity,hunger=20,energy=80)
        w['citizens'][2]['needs']['social']=99
    else:
        # Same initial scenarios used by the passing Stage 5D physical-policy QA.
        for c in w['citizens'][5:30]:
            p=c['known_places']['home']['position'].copy()
            c.update(position=p,activity='resting',navigation='ARRIVED')
            c['goal'].update(place='home',position=p.copy(),reason='need');c['needs']['energy']=50
        for index,p in ((31,[18,.12,-8]),(32,[-18,.12,-26]),(33,[-18,.12,78])):w['citizens'][index]['position']=p
        helper=w['citizens'][30];p=[-18,.12,-20]
        helper['position']=p.copy();helper['known_places']['park']['position']=p.copy()
        helper['goal'].update(place='park',position=p.copy(),reason='ideology');helper.update(activity='socializing',navigation='ARRIVED')
        helper['exceptional']['action']={'kind':'observe','request_id':None,'subject_id':None,'goal_id':helper['goal']['id'],'elapsed':0.,'selected_at':0.,'observed_position':None,'evidence_id':None}
        for index,p,social in ((0,[18,.12,-14],95),(1,[-18,.12,72],85),(2,[-16,.12,72],98),(3,[-18,.12,-32],95),(4,[-20,.12,-32],80)):
            c=w['citizens'][index];c['position']=p.copy();c['known_places']['park']['position']=p.copy();c['goal'].update(place='park',position=p.copy(),reason='need')
            c.update(activity='socializing',navigation='ARRIVED');c['needs'].update(social=social,hunger=20,energy=80)
    validate_world(w);store.commit('showcase_fixture',{});store.close();return ''

def probe(path):
    return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)],text=True))

def capture(mode):
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f'brother-eye-showcase-{mode}-') as d:
        folder=Path(d);db=folder/'world.sqlite3';frames=folder/'frames';frames.mkdir();seat=fixture(db,mode)
        command=['godot','--path',str(ROOT/'godot'),'--script','res://scripts/showcase_capture.gd','--','--with-simulation',f'--world-db={db}',f'--frames-dir={frames}',f'--showcase-mode={mode}',f'--seat-id={seat}']
        result=subprocess.run(command,capture_output=True,text=True,timeout=240)
        (EVIDENCE/f'{mode}.log').write_text(result.stdout+result.stderr);print(result.stdout,flush=True)
        assert result.returncode==0 and f'SHOWCASE_CAPTURE {mode}' in result.stdout and 'failures=0' in result.stdout and 'ERROR:' not in result.stdout+result.stderr
        deadline=time.monotonic()+10
        while list(folder.glob('session-*.json')) and time.monotonic()<deadline:time.sleep(.05)
        assert not list(folder.glob('session-*.json'))
        manifest=json.loads((frames/'capture.json').read_text());images=manifest.pop('frames')
        duration=images[-1]['time']-images[0]['time']+1/24
        manifest.update(captured_frames=len(images),capture_duration_seconds=duration,capture_average_fps=len(images)/duration)
        (EVIDENCE/f'{mode}.json').write_text(json.dumps(manifest,indent=2)+'\n')
        assert manifest['expected_outcome_verified'] and manifest['cores_unchanged']
        assert len(images)/duration>=10,'Capture too slow; retain completed chapters and retry this mode.'
        store=Store(db);validate_world(store.world);assert store.db.execute('PRAGMA quick_check').fetchone()[0]=='ok';store.close()
        lines=['ffconcat version 1.0']
        for i,item in enumerate(images):
            dt=images[i+1]['time']-item['time'] if i+1<len(images) else 1/24
            assert 0<dt<3,'Capture has an excessive gap.'
            lines.extend([f"file '{item['name']}'",f'duration {dt:.9f}'])
        lines.append(f"file '{images[-1]['name']}'");source=frames/'capture.ffconcat';source.write_text('\n'.join(lines)+'\n')
        output=EVIDENCE/f'{mode}.mp4'
        encode=subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','warning','-f','concat','-safe','0','-i',str(source),'-vf','scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p,fps=24','-c:v','libx264','-preset','fast','-crf','22','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_trc','bt709','-color_primaries','bt709','-movflags','+faststart','-an',str(output)],capture_output=True,text=True,timeout=180)
        (EVIDENCE/f'{mode}-encode.log').write_text(encode.stderr);assert encode.returncode==0,encode.stderr
        assert abs(float(probe(output)['format']['duration'])-duration)<.3
        print(f'PASS {mode}: live outcome, unchanged cores, SQLite integrity, {duration:.2f}s at {len(images)/duration:.1f} captured fps',flush=True)

def assemble():
    chapters=[('City and civilian life',EVIDENCE/'city.mp4'),('Arbiter of Dawn - local assistance',EVIDENCE/'arbiter.mp4'),('Attendant of Mysteries - verified information',EVIDENCE/'attendant.mp4'),('Martyr of Providence - voluntary coordination',EVIDENCE/'martyr.mp4'),('Sovereign of Unbound Will - companion assistance',EVIDENCE/'sovereign.mp4'),('Brother Eye - commands, cameras and autonomy',ROOT/'docs/previews/stage6e/Brother-Eye-Stage-6E.mp4'),('24-hour lighting study - separate from gameplay',ROOT/'docs/previews/day-cycle/Brother-Eye-24-Hour-Cycle.mp4')]
    for _,path in chapters:assert path.is_file(),path
    with tempfile.TemporaryDirectory(prefix='brother-eye-showcase-assemble-') as d:
        folder=Path(d);concat=folder/'chapters.ffconcat';concat.write_text('ffconcat version 1.0\n'+'\n'.join(f"file '{path}'" for _,path in chapters)+'\n')
        metadata=folder/'metadata.txt';lines=[';FFMETADATA1','title=Brother Eye - Complete City Showcase'];at=0;timeline=[]
        for label,path in chapters:
            duration=float(probe(path)['format']['duration']);end=at+duration
            lines.extend(['[CHAPTER]','TIMEBASE=1/1000',f'START={int(at*1000)}',f'END={int(end*1000)}',f'title={label}'])
            timeline.append({'title':label,'start_seconds':at,'duration_seconds':duration,'source':str(path.relative_to(ROOT))});at=end
        metadata.write_text('\n'.join(lines)+'\n')
        filters=['fps=24','format=yuv420p'];outcome_labels=[]
        # Show concise result captions derived from the actual recorded events.
        for index,mode in enumerate(('arbiter','attendant','martyr','sovereign'),start=1):
            manifest=json.loads((EVIDENCE/f'{mode}.json').read_text())
            actor=manifest['agents'][{'arbiter':0,'attendant':1,'martyr':2,'sovereign':3}[mode]]
            events=manifest['agent_history']
            assert manifest['expected_outcome_verified'] and manifest['cores_unchanged']
            if mode=='attendant':
                fact=next(e for e in events if e['agent_id']==actor['id'] and e['outcome']=='verified')
                assert fact['fact'] and fact['fact']['source_id']==fact['subject_id']
                label='RECORDED OUTCOME: local information verified after physical travel; the fact is saved in agent knowledge.'
            elif mode=='martyr':
                offered=next(e for e in events if e['agent_id']==actor['id'] and e['outcome']=='coordinated')
                completed=next(e for e in events if e['request_id']==offered['request_id'] and e['outcome']=='completed')
                assert completed['agent_id']==manifest['agents'][0]['id']
                assert abs(completed['before_social']-completed['after_social']-5)<1e-6
                count=sum(v=='completed' for v in actor['exceptional']['project']['outcomes'].values())
                assert count>=1
                label=f'RECORDED OUTCOME: a voluntary helper completed the delegated request; the project records {count} completed task.'
            else:
                completed=next(e for e in events if e['agent_id']==actor['id'] and e['outcome']=='completed')
                assert abs(completed['before_social']-completed['after_social']-5)<1e-6
                prefix='companion assistance' if mode=='sovereign' else 'local assistance'
                label=f'RECORDED OUTCOME: {prefix} completed; social need {completed["before_social"]:.1f}% -> {completed["after_social"]:.1f}% (one 5-point effect).'
            textfile=folder/f'outcome-{mode}.txt';textfile.write_text(label)
            item=timeline[index];begin=item['start_seconds']+item['duration_seconds']-9;end=begin+9
            enabled=f"between(t,{begin:.6f},{end:.6f})"
            filters.append(f"drawbox=x=35:y=91:w=1368:h=31:color=0x071118@0.98:t=fill:enable='{enabled}'")
            filters.append(f"drawtext=fontfile=/System/Library/Fonts/Supplemental/Arial.ttf:textfile={textfile}:expansion=none:fontsize=16:fontcolor=white:x=38:y=97:enable='{enabled}'")
            outcome_labels.append({'mode':mode,'caption':label,'start_seconds':begin,'end_seconds':end})
        output=EVIDENCE/'Brother-Eye-Complete-Showcase.mp4'
        command=['ffmpeg','-y','-hide_banner','-loglevel','warning','-f','concat','-safe','0','-i',str(concat),'-i',str(metadata),'-map','0:v:0','-map_metadata','1','-map_chapters','1','-vf',','.join(filters),'-c:v','libx264','-preset','medium','-crf','23','-maxrate','2100k','-bufsize','4200k','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_trc','bt709','-color_primaries','bt709','-movflags','+faststart','-an',str(output)]
        result=subprocess.run(command,capture_output=True,text=True,timeout=600)
        (EVIDENCE/'assemble.log').write_text(result.stderr);assert result.returncode==0,result.stderr
        details=probe(output);video=next(s for s in details['streams'] if s['codec_type']=='video')
        assert video['codec_name']=='h264' and video['pix_fmt']=='yuv420p' and (video['width'],video['height'])==(1440,900)
        assert abs(float(details['format']['duration'])-at)<.5
        assert 240<float(details['format']['duration'])<480
        assert output.stat().st_size<95*1024*1024,'Final showcase must fit a regular GitHub file.'
        decoded=subprocess.run(['ffmpeg','-v','error','-i',str(output),'-f','null','-'],capture_output=True,text=True,timeout=300)
        assert decoded.returncode==0 and not decoded.stderr,decoded.stderr
        actual_chapters=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_chapters','-of','json',str(output)],text=True))['chapters']
        assert len(actual_chapters)==len(timeline)
        for actual,planned in zip(actual_chapters,timeline):assert abs(float(actual['start_time'])-planned['start_seconds'])<.01
        for i,item in enumerate(timeline):
            point=item['start_seconds']+min(12,item['duration_seconds']*.4)
            subprocess.run(['ffmpeg','-y','-v','error','-ss',str(point),'-i',str(output),'-frames:v','1',str(EVIDENCE/f'chapter-{i+1}.jpg')],check=True,timeout=30)
        details.update(chapters=timeline,container_chapters=actual_chapters,outcome_captions=outcome_labels,verification='Full decode, format/duration, verified per-policy outcomes and file size passed. Chapter frame visual review recorded separately.',scope='Edited compilation of live disposable 50/34-person review worlds, existing 100-person Brother Eye review, and separately labeled offline lighting study. No production save or journal touched; silent.')
        (EVIDENCE/'verification.json').write_text(json.dumps(details,indent=2)+'\n')
        print(f'PASS complete showcase: {at:.2f}s, {output.stat().st_size/1024/1024:.1f} MiB; {output}',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--mode',choices=(*MODES,'all','assemble'),default='all');args=parser.parse_args()
    if args.mode in MODES:capture(args.mode)
    elif args.mode=='assemble':assemble()
    else:
        for mode in MODES:capture(mode)
        assemble()
