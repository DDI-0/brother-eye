"""Real service/renderer evaluation check using an isolated hungry resident."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from backend.store import Store
from backend.citizens import plan

def run(native=False):
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage4b-') as name:
        folder=Path(name);db=folder/'world.sqlite3'
        store=Store(db);store.world.update(paused=True,time_scale=60)
        c=store.world['citizens'][0];c['position']=[18,.12,-12];c['needs']['hunger']=92
        plan(c,0);store.commit('qa_fixture',{});store.close()
        command=['godot']+([] if native else ['--headless'])+['--path',str(ROOT/'godot'),'--script','res://scripts/stage4b_check.gd','--','--with-simulation','--evaluation-review',f'--world-db={db}']
        if native:command.append('--capture-evaluation')
        result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
        print(result.stdout,end='',flush=True)
        if result.returncode or 'ERROR:' in result.stdout or 'FAIL ' in result.stdout:raise RuntimeError('Evaluation acceptance failed')
        end=time.monotonic()+5
        while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
        assert not list(folder.glob('session-*.json'))
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            world=json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            assert len(world['citizens'])==34 and 'assessment' not in world
        print('PASS assessment remains derived; saved world and service lifecycle intact')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true');run(parser.parse_args().native)
