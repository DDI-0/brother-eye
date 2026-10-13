"""Disposable native/headless three-policy and real voluntary-coordination acceptance."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store, validate_world

def run(native=False):
    evidence=ROOT/'docs/previews/stage5d';evidence.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage5d-') as name:
        folder=Path(name);db=folder/'world.sqlite3';probe=folder/'probe.json'
        store=Store(db);w=store.world;w.update(paused=True,time_scale=1)
        # Quiet the unrelated fixture residents at their own homes; leave normal saves untouched.
        for c in w['citizens'][5:30]:
            point=c['known_places']['home']['position'].copy()
            c.update(position=point,activity='resting',navigation='ARRIVED')
            c['goal'].update(place='home',position=point.copy(),reason='need');c['needs']['energy']=50
        for index,position in ((31,[18,.12,-8]),(32,[-18,.12,-26]),(33,[-18,.12,78])):w['citizens'][index]['position']=position
        helper=w['citizens'][30];point=[-18,.12,-20]
        helper['position']=point.copy();helper['known_places']['park']['position']=point.copy()
        helper['goal'].update(place='park',position=point.copy(),reason='ideology')
        helper.update(activity='socializing',navigation='ARRIVED')
        helper['exceptional']['action']={'kind':'observe','request_id':None,'subject_id':None,'goal_id':helper['goal']['id'],'elapsed':0.,'selected_at':0.,'observed_position':None,'evidence_id':None}
        for index,point,social in ((0,[18,.12,-14],95),(1,[-18,.12,72],85),(2,[-16,.12,72],98),(3,[-18,.12,-32],95),(4,[-20,.12,-32],80)):
            c=w['citizens'][index];c['position']=point.copy();c['known_places']['park']['position']=point.copy();c['goal'].update(place='park',position=point.copy(),reason='need')
            c.update(activity='socializing',navigation='ARRIVED');c['needs'].update(social=social,hunger=20,energy=80)
        validate_world(w);store.commit('stage5d_fixture',{});store.close()
        for phase in ('write','read'):
            command=['godot']+([] if native else ['--headless','--fixed-fps','60'])+['--path',str(ROOT/'godot'),'--script','res://scripts/stage5d_check.gd','--','--with-simulation','--exceptional-review',f'--world-db={db}',f'--probe={probe}',f'--phase={phase}']
            if native:command.append('--capture-stage5d')
            result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=150)
            print(result.stdout,end='',flush=True)
            if result.returncode!=0:
                with sqlite3.connect(db) as failed:
                    (evidence/'failed-trace.json').write_text(failed.execute('SELECT state_json FROM world').fetchone()[0])
            assert result.returncode==0 and f'STAGE5D_CHECK {phase} failures=0' in result.stdout and 'ERROR:' not in result.stdout and 'FAIL ' not in result.stdout
            end=time.monotonic()+8
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')),'Owned backend failed to stop'
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA user_version').fetchone()[0]==8
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            world=json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0]);validate_world(world)
            events=[event for data, in connection.execute('SELECT data_json FROM events') for event in json.loads(data).get('agent_events',[])]
            completions=[e for e in events if e['outcome']=='completed'];assert len({e['request_id'] for e in completions})==len(completions)
            assert any(e['outcome']=='verified' and e['fact'] for e in events)
            assert any(e['outcome']=='coordinated' for e in events)
            assert all(abs(e['before_social']-e['after_social']-5)<1e-9 for e in completions)
            (evidence/('native-trace.json' if native else 'trace.json')).write_text(json.dumps({'schema':8,'clock':world['clock_seconds'],'agents':world['citizens'][30:],'events':events},indent=2)+'\n')
        print('PASS schema 8, verified local facts, voluntary task claim, unique physical rewards and owned shutdown')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true');run(parser.parse_args().native)
