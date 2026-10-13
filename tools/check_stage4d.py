"""Real control room, historical paging, live cameras and ACK-only feedback."""
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
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from backend.service import Service, envelope
from backend.store import Store


def run(native=False):
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage4d-') as name:
        folder=Path(name);db=folder/'world.sqlite3';probe=folder/'probe.json'
        store=Store(db);store.world.update(paused=True,time_scale=60)
        store.world['citizens'][0]['position']=[18,.12,-8]
        service=Service(store,'a'*64,os.getpid())
        for _ in range(70):
            c=store.world['citizens'][0]
            service.command(envelope('intervene',{'world_id':store.world['world_id'],'citizen_id':c['id'],
                'expected_goal_id':c['goal']['id'],'expected_intervention_id':c['intervention']['id'] if c['intervention'] else None,
                'action':'assign_destination','place':'food','reason':'Historical fixture'},str(uuid.uuid4())))
        store.close()
        for phase in ('write','read'):
            cmd=['godot']+([] if native else ['--headless'])+['--path',str(ROOT/'godot'),'--script','res://scripts/stage4d_check.gd','--','--with-simulation','--control-room-review',f'--world-db={db}',f'--probe={probe}',f'--phase={phase}']
            if native:cmd.append('--capture-control-room')
            try:
                result=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
            except subprocess.TimeoutExpired as error:
                output=error.stdout or ''
                print(output.decode() if isinstance(output,bytes) else output,flush=True)
                raise
            print(result.stdout,end='',flush=True)
            assert result.returncode==0 and f'STAGE4D_CHECK {phase} failures=0' in result.stdout and 'ERROR:' not in result.stdout and 'FAIL ' not in result.stdout,phase+' acceptance failed'
            end=time.monotonic()+8
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')),'Owned service did not stop'
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            assert connection.execute("SELECT COUNT(*) FROM events WHERE kind='world_created'").fetchone()[0]==1
            assert connection.execute("SELECT COUNT(*) FROM receipts WHERE json_extract(request_json,'$.type')='query_interventions'").fetchone()[0]==0
            assert connection.execute("SELECT COUNT(*) FROM receipts WHERE json_extract(request_json,'$.type')='intervene'").fetchone()[0]==82
        print('PASS read-only queries create no receipts; replay adds no duplicate effect; one world and SQLite integrity retained')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true');run(parser.parse_args().native)
