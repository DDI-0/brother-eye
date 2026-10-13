"""Inspection acceptance against a disposable world; optional native visual capture."""
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
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage4a-') as name:
        folder=Path(name);db=folder/'world.sqlite3';probe=folder/'inspection.json'
        store=Store(db);store.world.update(paused=True,time_scale=60)
        person=store.world['citizens'][0];person['position']=[18,.12,-12];person['needs']['hunger']=80
        plan(person,store.world['clock_seconds']);store.commit('qa_fixture',{});store.close()
        for phase in ('write','read'):
            command=['godot']+([] if native else ['--headless'])+['--path',str(ROOT/'godot'),
                '--script','res://scripts/stage4a_check.gd','--','--with-simulation','--inspection-review',
                f'--world-db={db}',f'--probe={probe}',f'--phase={phase}']
            if native:command.append('--capture-inspection')
            result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
            print(result.stdout,end='',flush=True)
            if result.returncode or 'ERROR:' in result.stdout or 'FAIL ' in result.stdout:raise RuntimeError(f'{phase} inspection failed')
            end=time.monotonic()+5
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')),'App-owned service did not stop'
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            world=json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            assert len(world['citizens'])==34
        print('PASS inspection across two launches; 34 identities and SQLite integrity retained')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--native',action='store_true')
    run(parser.parse_args().native)
