"""Native controlled visual-budget comparison in a disposable 50-person city."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
with tempfile.TemporaryDirectory(prefix='brother-eye-stage6c-') as name:
    folder=Path(name);db=folder/'world.sqlite3';store=Store(db,tier=1)
    store.world['paused']=True;store.commit('visual_fixture',{});store.close()
    r=subprocess.run(['godot','--path',str(ROOT/'godot'),'--script','res://scripts/stage6c_check.gd','--','--with-simulation',f'--world-db={db}'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=200)
    print(r.stdout,flush=True)
    assert r.returncode==0 and 'STAGE6C_CHECK failures=0' in r.stdout and 'ERROR:' not in r.stdout
    deadline=time.monotonic()+10
    while list(folder.glob('session-*.json')) and time.monotonic()<deadline:time.sleep(.05)
    assert not list(folder.glob('session-*.json')),'Owned service failed to stop'
    store=Store(db);validate_world(store.world);assert len(store.world['citizens'])==50
    assert store.db.execute('PRAGMA quick_check').fetchone()[0]=='ok';store.close()
    print('PASS Stage 6C visual budgets, control-room camera priorities and durable integrity')
