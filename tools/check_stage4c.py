"""Real intervention UI, physical travel, process interruption and journal recovery."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from backend.store import Store


def run(native=False):
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage4c-') as name:
        folder=Path(name); db=folder/'world.sqlite3'; probe=folder/'probe.json'
        store=Store(db); store.world.update(paused=True,time_scale=60)
        store.world['citizens'][0]['position']=[18,.12,-8]
        store.commit('qa_fixture',{}); store.close()
        for phase in ('write','read','journal','replay'):
            command=['godot']+([] if native else ['--headless'])+['--path',str(ROOT/'godot'),'--script','res://scripts/stage4c_check.gd','--','--with-simulation','--intervention-review',f'--world-db={db}',f'--phase={phase}',f'--probe={probe}']
            if native:command.append('--capture-interventions')
            result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
            print(result.stdout,end='',flush=True)
            assert result.returncode==0 and f'STAGE4C_CHECK {phase} failures=0' in result.stdout and 'ERROR:' not in result.stdout and 'FAIL ' not in result.stdout, phase+' failed'
            end=time.monotonic()+8
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')), 'Owned backend did not stop'
            if phase=='replay':
                request_id=json.loads(probe.read_text())['command']
                with sqlite3.connect(db) as connection:
                    assert connection.execute('SELECT COUNT(*) FROM receipts WHERE command_id=?',(request_id,)).fetchone()[0]==1
                    data=[json.loads(row[0]) for row in connection.execute("SELECT data_json FROM events WHERE kind='intervene'")]
                    accepted=[e for row in data for e in row['interventions'] if e['command_id']==request_id and e['outcome']=='accepted']
                    assert len(accepted)==1
                print('PASS frontend interruption has exactly one durable receipt and accepted audit event')
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            assert connection.execute('PRAGMA user_version').fetchone()[0]==8
            world=json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            assert len(world['citizens'])==34 and world['citizens'][0]['intervention'] is None
            assert connection.execute("SELECT COUNT(*) FROM events WHERE kind='world_created'").fetchone()[0]==1
        print('PASS one isolated world, schema 8, SQLite integrity and service lifecycle intact')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true');run(parser.parse_args().native)
