"""Native 50/100-person acceptance and RSS sampling; disposable saves only."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
from backend.city_life import spot_goal,_clear
from backend.retention import command_id,status,RECEIPT_LIMIT,PRUNE_INTERVAL
from backend.service import Service,envelope

def fixture(db,tier):
    s=Store(db,tier=tier);w=s.world;w.update(paused=True,time_scale=1)
    seated=next(c for c in w['citizens'] if any(spot['pose']=='sit' for spot in c['known_places']['home']['spots']))
    index=next(i for i,spot in enumerate(seated['known_places']['home']['spots']) if spot['pose']=='sit')
    seated['goal']=spot_goal(seated,'home','need',0,index);p=seated['goal']['position']
    seated.update(position=[p[0]+(-1.8 if p[0]>0 else 1.8),p[1],p[2]],activity='travelling',navigation='TRAVELLING')
    seated['needs'].update(energy=30,hunger=20,social=35)
    # Initial disposable test placement, never a runtime teleport or production edit.
    target=None
    for c in w['citizens']:
        if c['kind']!='civilian' or c is seated:continue
        p=c['known_places']['food']['position']
        for dz in (2.5,-2.5,3.0,-3.0):
            q=[p[0],p[1],p[2]+dz]
            if _clear(q[0],q[2],q[1],[other['position'] for other in w['citizens'] if other is not c]):
                target=c;c.update(position=q,activity='travelling',navigation='TRAVELLING');break
        if target:break
    assert target
    validate_world(w);s.commit('stage6e_fixture',{});s.close()
    return target['id'],seated['id']

def run(tier,headless=False):
    evidence=ROOT/'docs/previews/stage6e';evidence.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage6e-') as d:
        folder=Path(d);db=folder/'world.sqlite3';probe=folder/'probe.json';target,seat=fixture(db,tier)
        memory=[]
        for phase in ('write','read'):
            command=['godot',*(['--headless'] if headless else []),'--path',str(ROOT/'godot'),'--script','res://scripts/stage6e_check.gd','--','--with-simulation',f'--world-db={db}',f'--phase={phase}',f'--probe={probe}',f'--review-tier={tier}',f'--target-id={target}',f'--seat-id={seat}']
            log=evidence/f'{tier}-{phase}.log'
            with log.open('w') as output:
                proc=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT);started=time.monotonic()
                while proc.poll() is None:
                    if time.monotonic()-started>220:
                        proc.terminate();raise TimeoutError(log)
                    pids=[proc.pid]
                    for ready in folder.glob('session-*.json'):
                        try:pids.append(json.loads(ready.read_text())['pid'])
                        except (OSError,ValueError,KeyError):pass
                    rows=[]
                    for pid in pids:
                        result=subprocess.run(['ps','-o','rss=','-p',str(pid)],text=True,capture_output=True)
                        try:rows.append(int(result.stdout.strip())*1024)
                        except ValueError:rows.append(0)
                    if phase=='write':memory.append({'elapsed_seconds':round(time.monotonic()-started,2),'godot_rss_bytes':rows[0],'backend_rss_bytes':rows[1] if len(rows)>1 else 0})
                    time.sleep(.5)
            text=log.read_text();print(text,flush=True)
            assert proc.returncode==0 and f'STAGE6E_CHECK {phase} tier={tier} failures=0' in text and 'ERROR:' not in text and 'FAIL ' not in text,log
            deadline=time.monotonic()+10
            while list(folder.glob('session-*.json')) and time.monotonic()<deadline:time.sleep(.05)
            assert not list(folder.glob('session-*.json'))
        s=Store(db);validate_world(s.world);assert s.world['paused'];assert s.db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
        snapshot=s.snapshot();service=Service(s,'a'*64,0);timings=[]
        # Exercise retained sequenced receipts at the larger snapshot size.
        for _ in range(200):
            serial=s.world['command_serial']+1;request={**envelope('save',{},command_id(s.world['world_id'],serial)),'serial':serial}
            start=time.perf_counter();service.command(request);timings.append((time.perf_counter()-start)*1000)
        assert s.world['citizens']==snapshot['citizens'] and s.world['clock_seconds']==snapshot['clock_seconds']
        assert s.db.execute('SELECT count(*) FROM receipts').fetchone()[0]<=RECEIPT_LIMIT+PRUNE_INTERVAL-1
        s.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');timings.sort()
        result={'population':len(s.world['citizens']),'schema':s.db.execute('PRAGMA user_version').fetchone()[0],'db_bytes':db.stat().st_size,'save_median_ms':timings[len(timings)//2],'save_p95_ms':timings[int(len(timings)*.95)],'save_max_ms':max(timings),'retention':status(s.db),'peak_godot_rss_bytes':max(x['godot_rss_bytes'] for x in memory),'peak_backend_rss_bytes':max(x['backend_rss_bytes'] for x in memory),'rss_samples':memory,'scope':'Process RSS sampled every 0.5 s including startup, not unique unified-memory accounting. Save timings are offline backend commands after native acceptance; not gameplay frame times.'}
        s.close();(evidence/f'storage-memory-{tier}.json').write_text(json.dumps(result,indent=2)+'\n')
        print(f'PASS tier {tier}: native activity, navigation, command, seating, restore, bounded receipts and SQLite integrity',flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--tier',type=int,choices=(1,2),default=2);parser.add_argument('--headless',action='store_true');args=parser.parse_args();run(args.tier,args.headless)
