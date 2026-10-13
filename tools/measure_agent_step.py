"""Focused backend step cost only; not a rendering or population-scaling benchmark."""
import json
import argparse
import os
from pathlib import Path
import statistics
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.service import Service
from backend.store import Store

def run(output):
    with tempfile.TemporaryDirectory(prefix='brother-eye-agent-budget-') as name:
        store=Store(Path(name)/'world.sqlite3');service=Service(store,'a'*64,os.getpid())
        timings=[]
        for _ in range(1000):
            start=time.perf_counter();service.advance(.05);timings.append((time.perf_counter()-start)*1000)
        ordered=sorted(timings)
        result={'scope':'1000 backend 50 ms simulation steps, 34 seeded residents, four active policies; no renderer or physical movement reports',
                'median_ms':statistics.median(timings),'p95_ms':ordered[949],'p99_ms':ordered[989],
                'max_ms':ordered[-1],'step_budget_ms':50,'over_budget_steps':sum(t>50 for t in timings)}
        store.close()
    target=ROOT/output;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',default='docs/previews/stage5e/backend-step-cost.json');run(parser.parse_args().output)
