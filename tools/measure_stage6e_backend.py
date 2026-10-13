"""Backend-only cost sampling in independent 50/100-person disposable worlds."""
import json
from pathlib import Path
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
from backend.service import Service,envelope
from backend.retention import command_id

def metrics(values):
    values.sort()
    return {'samples':len(values),'median_ms':values[len(values)//2],'p95_ms':values[int(len(values)*.95)],'max_ms':max(values)}
def run():
    results=[]
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage6e-cost-') as d:
        for tier in (1,2):
            store=Store(Path(d)/f'{tier}.sqlite3',tier=tier);service=Service(store,'a'*64,0)
            clocks=[];saves=[]
            for _ in range(400):
                start=time.perf_counter();service.advance(.05);clocks.append((time.perf_counter()-start)*1000)
            store.world['paused']=True
            for _ in range(200):
                serial=store.world['command_serial']+1
                request={**envelope('save',{},command_id(store.world['world_id'],serial)),'serial':serial}
                start=time.perf_counter();service.command(request);saves.append((time.perf_counter()-start)*1000)
            validate_world(store.world)
            results.append({'population':len(store.world['citizens']),'clock_step':metrics(clocks),'save':metrics(saves)})
            store.close()
    result={'results':results,'scope':'Backend-only synchronous 0.05-second steps and saves in separate disposable worlds; no Godot physical reports, no networking, not full gameplay CPU/frame timing.'}
    (ROOT/'docs/previews/stage6e/backend-cost.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':run()
