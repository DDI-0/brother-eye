"""Native seating/departure, preserved migration, budgeting and sustained 50-person measurements."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
from backend.city_life import spot_goal
with tempfile.TemporaryDirectory(prefix='brother-eye-pre6c-fixes-') as d:
    folder=Path(d);db=folder/'world.sqlite3';store=Store(db);w=store.world
    w.update(paused=True,time_scale=1)
    seated=next(c for c in w['citizens'] if any(s['pose']=='sit' for s in c['known_places']['home']['spots']))
    spots=seated['known_places']['home']['spots'];index=next(i for i,s in enumerate(spots) if s['pose']=='sit')
    seated['goal']=spot_goal(seated,'home','need',w['clock_seconds'],index)
    p=seated['goal']['position'];seated.update(position=[p[0]+(-1.8 if p[0]>0 else 1.8),p[1],p[2]],activity='travelling',navigation='TRAVELLING')
    seated['needs'].update(energy=30,hunger=20,social=35)
    strolling=next(c for c in w['citizens'] if c['kind']=='civilian' and c['id']!=seated['id'])
    strolling['goal']=spot_goal(strolling,'park','schedule',w['clock_seconds'],0)
    p=strolling['goal']['position'];strolling.update(position=[p[0]+1.5,p[1],p[2]],activity='socializing',navigation='TRAVELLING')
    strolling['needs'].update(hunger=20,energy=80,social=35)
    # Keep this mid-venue stroll through planner refresh: the selected schedule at 08:00 is park.
    strolling['schedule']=[{'hour':0,'place':'home'},{'hour':1,'place':'work'},{'hour':2,'place':'food'},{'hour':3,'place':'work'},{'hour':4,'place':'park'},{'hour':23,'place':'home'}]
    validate_world(w);store.commit('physical_fixture',{});store.close()
    command=['godot','--path',str(ROOT/'godot'),'--script','res://scripts/pre6c_fixes_check.gd','--','--with-simulation','--population-tier=1',f'--world-db={db}',f'--seat-id={seated["id"]}',f'--stroll-id={strolling["id"]}']
    r=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180);print(r.stdout,flush=True)
    assert r.returncode==0 and 'PRE6C_FIXES failures=0' in r.stdout and 'ERROR:' not in r.stdout
    end=time.monotonic()+10
    while list(folder.glob('session-*.json')) and time.monotonic()<end:time.sleep(.05)
    assert not list(folder.glob('session-*.json'))
    store=Store(db);validate_world(store.world);assert store.db.execute('PRAGMA quick_check').fetchone()[0]=='ok';store.close()
    print('PASS physical seating/stroll, distance budgets, 50-person native sample and durable integrity')
