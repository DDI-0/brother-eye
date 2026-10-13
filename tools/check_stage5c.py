"""Disposable real-city Arbiter travel/assistance/crash/relaunch acceptance."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from backend.store import Store


def run(native=False, evidence_dir='docs/previews/stage5c'):
    evidence=ROOT/evidence_dir;evidence.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage5c-') as name:
        folder=Path(name);db=folder/'world.sqlite3';probe=folder/'probe.json'
        store=Store(db);w=store.world;w.update(paused=True,time_scale=1)
        a=w['citizens'][30];a.update(position=[18,.12,-8])
        for index,severity in ((0,95),(1,85)):
            c=w['citizens'][index];p=[18+index*2,.12,-14]
            c['known_places']['park']['position']=p;c['goal'].update(place='park',position=p,reason='need')
            c.update(position=p,activity='socializing',navigation='ARRIVED');c['needs'].update(social=severity,hunger=20,energy=80)
        w['citizens'][2]['needs']['social']=99
        store.commit('stage5c_fixture',{});store.close()
        for phase in ('write','read'):
            cmd=['godot']+([] if native else ['--headless','--fixed-fps','60'])+['--path',str(ROOT/'godot'),'--script','res://scripts/stage5c_check.gd','--','--with-simulation','--exceptional-review',f'--world-db={db}',f'--probe={probe}',f'--phase={phase}']
            if native:cmd.append('--capture-stage5c')
            result=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=145)
            print(result.stdout,end='',flush=True)
            assert result.returncode==0 and f'STAGE5C_CHECK {phase} failures=0' in result.stdout and 'ERROR:' not in result.stdout and 'FAIL ' not in result.stdout
            end=time.monotonic()+8
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')),'Owned service did not stop'
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA user_version').fetchone()[0]==8
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            world=json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            events=[e for e in world['agent_history'] if e['outcome']=='completed']
            assert len(events)==1 and events[0]['before_social']-events[0]['after_social']==5
            durable=[e for (data,) in connection.execute("SELECT data_json FROM events") for e in json.loads(data).get('agent_events',[]) if e['outcome']=='completed']
            assert [e['id'] for e in durable]==[e['id'] for e in events]
            (evidence/('native-trace.json' if native else 'trace.json')).write_text(json.dumps({'schema':8,'agents':world['citizens'][30:],'history':world['agent_history'],'clock':world['clock_seconds']},indent=2))
        print('PASS schema 8, one atomic physical reward/audit, bounded learning, no offline advancement and owned shutdown')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true');parser.add_argument('--evidence-dir',default='docs/previews/stage5c');args=parser.parse_args();run(args.native,args.evidence_dir)
