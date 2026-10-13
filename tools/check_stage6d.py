"""Disposable retention/replay/window acceptance and long-run hot-database sample."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
from backend.service import Service,envelope
from backend.retention import command_id,prune,status,RECEIPT_LIMIT,PRUNE_INTERVAL,RECENT_EVENTS,SIGNIFICANT_EVENTS
from tools.compact_database import compact

def run(native=False):
    evidence=ROOT/'docs/previews/stage6d';evidence.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage6d-') as d:
        folder=Path(d);db=folder/'world.sqlite3';probe=folder/'probe.json';store=Store(db,tier=1);store.world['paused']=True
        service=Service(store,'a'*64,os.getpid())
        def assign(serial=None):
            w=store.world;c=w['citizens'][0]
            payload={'world_id':w['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':c['intervention']['id'] if c['intervention'] else None,'action':'assign_destination','place':'home','reason':'Retention history fixture'}
            return envelope('intervene',payload,str(uuid.uuid4())) if serial is None else {**envelope('intervene',payload,command_id(w['world_id'],serial)),'serial':serial}
        legacy=assign();service.command(legacy);first=None
        for _ in range(600):
            request=assign(store.world['command_serial']+1);service.command(request)
            if first is None:first=request
        with store.db:prune(store.db)
        w=store.snapshot();serial=w['command_serial']+1
        fresh={**envelope('save',{},command_id(w['world_id'],serial)),'serial':serial}
        Path(str(db)+'.pending.json').write_text(json.dumps({'world_id':w['world_id'],'last_serial':serial,'commands':[first,legacy,fresh]}))
        store.close()
        for phase in ('write','read'):
            cmd=['godot']+([] if native else ['--headless','--fixed-fps','60'])+['--path',str(ROOT/'godot'),'--script','res://scripts/stage6d_check.gd','--','--with-simulation','--control-room-review',f'--world-db={db}',f'--probe={probe}',f'--phase={phase}']
            if native:cmd.append('--capture-stage6d')
            r=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=130);print(r.stdout,end='',flush=True)
            assert r.returncode==0 and f'STAGE6D_CHECK {phase} failures=0' in r.stdout and 'ERROR:' not in r.stdout and 'SCRIPT ERROR' not in r.stdout
            end=time.monotonic()+10
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')),'Owned backend did not stop'
        store=Store(db);validate_world(store.world);service=Service(store,'a'*64,os.getpid())
        fresh_id=json.loads(probe.read_text())['fresh_command']
        assert store.db.execute('SELECT count(*) FROM receipts WHERE command_id=?',(fresh_id,)).fetchone()[0]==1
        timings=[];sizes=[]
        for index in range(1800):
            serial=store.world['command_serial']+1
            request={**envelope('save',{},command_id(store.world['world_id'],serial)),'serial':serial}
            start=time.perf_counter();service.command(request);timings.append((time.perf_counter()-start)*1000)
            if index in (599,1199,1799):
                store.db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
                sizes.append({'commands':index+1,'bytes':db.stat().st_size,'receipts':store.db.execute('SELECT count(*) FROM receipts').fetchone()[0],'events':store.db.execute('SELECT count(*) FROM events').fetchone()[0]})
        assert store.db.execute('SELECT count(*) FROM receipts').fetchone()[0]<=RECEIPT_LIMIT+PRUNE_INTERVAL-1
        assert store.db.execute('SELECT count(*) FROM events').fetchone()[0]<=RECENT_EVENTS+SIGNIFICANT_EVENTS+PRUNE_INTERVAL+10
        assert store.db.execute('SELECT count(*) FROM legacy_receipts').fetchone()[0]==1
        assert sizes[-1]['bytes']<=sizes[0]['bytes']*1.20 # Freed pages reused rather than growing per snapshot.
        state=store.snapshot();details=status(store.db);store.close()
        compaction=compact(db);store=Store(db);assert store.snapshot()==state;store.close()
        timings.sort()
        result={'scope':'1800 sequenced save commands, 50 residents, 600 prior intervention commands, paused; backend/SQLite only, not a gameplay frame benchmark','sizes':sizes,'command_median_ms':timings[len(timings)//2],'command_p95_ms':timings[int(len(timings)*.95)],'command_max_ms':max(timings),'retention':details,'compaction':compaction,'legacy_retry_records':1,'command_serial':state['command_serial']}
        (evidence/('retention-native.json' if native else 'retention-headless.json')).write_text(json.dumps(result,indent=2)+'\n')
        print('PASS bounded hot tables, stable file reuse, offline compaction, preserved world and exactly one legacy retry record')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true');run(parser.parse_args().native)
