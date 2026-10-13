"""Native 34-person measurement in an isolated world, never the user's save."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
with tempfile.TemporaryDirectory(prefix='brother-eye-stage5e-') as name:
    folder=Path(name);db=folder/'world.sqlite3'
    store=Store(db);store.close()
    result=subprocess.run(['godot','--path',str(ROOT/'godot'),'--script','res://scripts/stage5e_check.gd','--','--with-simulation',f'--world-db={db}'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=140)
    print(result.stdout,flush=True)
    assert result.returncode==0 and 'STAGE5E_CHECK failures=0' in result.stdout and 'ERROR:' not in result.stdout
    end=time.monotonic()+10
    while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
    assert not list(folder.glob('session-*.json'))
    store=Store(db);validate_world(store.world)
    assert store.db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
    trace={'schema':store.db.execute('PRAGMA user_version').fetchone()[0],'population':len(store.world['citizens']),'clock':store.world['clock_seconds'],'agents':store.world['citizens'][30:]}
    (ROOT/'docs/previews/stage5e/native-state.json').write_text(json.dumps(trace,indent=2)+'\n');store.close()
    print('PASS 34-person native sample, immutable cores, valid durable state and owned shutdown')
