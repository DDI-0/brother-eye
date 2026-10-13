"""Schema-4 migration, old journal receipt, astronaut foundation and physical overrides."""
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
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage5b-') as name:
        folder=Path(name);db=folder/'world.sqlite3';probe=folder/'probe.json';legacy=folder/'legacy.json'
        store=Store(db);store.world['citizens']=store.world['citizens'][:30]
        store.world.update(paused=True,time_scale=1)
        c=store.world['citizens'][0]
        request=envelope('intervene',{'world_id':store.world['world_id'],'citizen_id':c['id'],
            'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,'action':'assign_destination',
            'place':'food','reason':'Preserve a pre-migration override'},str(uuid.uuid4()))
        Service(store,'a'*64,os.getpid()).command(request)
        legacy.write_text(json.dumps(store.snapshot()))
        receipt=store.db.execute('SELECT request_json,response_json FROM receipts WHERE command_id=?',(request['id'],)).fetchone()
        store.db.execute('PRAGMA user_version=4');store.db.commit();store.close()
        Path(str(db)+'.pending.json').write_text(json.dumps({'world_id':request['payload']['world_id'],'commands':[request]}))
        for phase in ('write','read'):
            cmd=['godot']+([] if native else ['--headless','--fixed-fps','60'])+['--path',str(ROOT/'godot'),
                '--script','res://scripts/stage5b_check.gd','--','--with-simulation','--exceptional-review',
                f'--world-db={db}',f'--legacy={legacy}',f'--probe={probe}',f'--phase={phase}']
            if native:cmd.append('--capture-stage5b')
            try:result=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=150)
            except subprocess.TimeoutExpired as error:
                print(error.stdout,flush=True);raise
            print(result.stdout,end='',flush=True)
            assert result.returncode==0 and f'STAGE5B_CHECK {phase} failures=0' in result.stdout and 'ERROR:' not in result.stdout and 'FAIL ' not in result.stdout
            end=time.monotonic()+8
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')),'Owned service did not stop'
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA user_version').fetchone()[0]==8
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            assert connection.execute("SELECT COUNT(*) FROM events WHERE kind='exceptional_agents_migrated'").fetchone()[0]==1
            assert connection.execute("SELECT COUNT(*) FROM events WHERE kind='world_created'").fetchone()[0]==1
            assert connection.execute('SELECT request_json,response_json FROM receipts WHERE command_id=?',(request['id'],)).fetchone()==receipt
            world=json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            assert len(world['citizens'])==34 and len({c['id'] for c in world['citizens']})==34
            original=json.loads(legacy.read_text())
            assert world['citizens'][0]['intervention']['id']==original['citizens'][0]['intervention']['id']
        print('PASS schema 8, exactly one migration, 34 stable identities, original receipt unchanged and owned shutdown')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true');run(parser.parse_args().native)
