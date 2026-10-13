"""Real app population acceptance against an isolated save."""
from pathlib import Path
import json
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from backend.store import Store

def run():
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage3e-') as name:
        folder=Path(name);db=folder/'world.sqlite3';probe=folder/'probe.json'
        store=Store(db);store.world['paused']=True;store.commit('qa_fixture',{})
        old=store.snapshot();old['citizens']=old['citizens'][:1]
        old['citizens'][0].pop('kind');old['citizens'][0].pop('appearance')
        store.db.execute('UPDATE world SET state_json=?',(json.dumps(old),))
        store.db.execute('PRAGMA user_version=2');store.db.commit();store.close()
        for phase in ('write','read','journal','replay'):
            result=subprocess.run(['godot','--headless','--path',str(ROOT/'godot'),'--fixed-fps','60',
                '--script','res://scripts/stage3e_check.gd','--','--with-simulation',
                f'--world-db={db}',f'--phase={phase}',f'--probe={probe}'],
                text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=150)
            print(result.stdout,end='',flush=True)
            if result.returncode or 'ERROR:' in result.stdout or 'FAIL ' in result.stdout:raise RuntimeError(f'{phase} failed')
            if phase=='read':
                identifier=re.search(r'REPLAYED_COMMAND ([a-f0-9-]+)',result.stdout)[1]
                with sqlite3.connect(db) as connection:
                    assert connection.execute('SELECT COUNT(*) FROM receipts WHERE command_id=?',(identifier,)).fetchone()[0]==1
                print('PASS recovered batch has exactly one receipt',flush=True)
            end=time.monotonic()+5
            while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
            assert not list(folder.glob('session-*.json')),'Service did not stop'
            print('PASS app-owned backend stops after close',flush=True)
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0]=='ok'
            world=json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            assert len({c['id'] for c in world['citizens']})==34
        print('PASS 34 durable people across four launches; SQLite integrity ok')
if __name__=='__main__':run()
