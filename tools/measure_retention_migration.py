"""Disposable large schema-7 receipt fixture; no normal save access."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import uuid
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
from backend.service import Service,envelope
from tools.compact_database import compact
from backend.retention import RECEIPT_LIMIT
with tempfile.TemporaryDirectory(prefix='brother-eye-retention-migration-') as d:
    path=Path(d)/'world.sqlite3';s=Store(path,tier=1);w=s.snapshot();w['paused']=True;w.pop('command_serial')
    count=1200;first=None;last=None
    with s.db:
        s.db.execute('DROP TABLE legacy_receipts');s.db.execute('DROP TABLE retention')
        s.db.execute('DROP INDEX receipt_order');s.db.execute('ALTER TABLE receipts DROP COLUMN committed_seq')
        for i in range(count):
            request=envelope('save',{},str(uuid.uuid4()));w['revision']=i+1
            response=envelope('ack',{'command':'save','state':w},request['id'])
            s.db.execute('INSERT INTO receipts VALUES(?,?,?)',(request['id'],json.dumps(request),json.dumps(response)))
            s.db.execute('INSERT INTO events(at,kind,data_json) VALUES(?,?,?)',('2026-10-13T00:00:00Z','save',json.dumps({'revision':i+1})))
            if i==0:first=request
            last=(request,json.loads(json.dumps(response)))
        s.db.execute('UPDATE world SET state_json=?',(json.dumps(w),));s.db.execute('PRAGMA user_version=7')
    s.close();before_bytes=path.stat().st_size
    started=time.perf_counter();s=Store(path);migration_ms=(time.perf_counter()-started)*1000
    validate_world(s.world);service=Service(s,'a'*64,os.getpid())
    assert s.world['citizens']==w['citizens'] and s.world['clock_seconds']==w['clock_seconds']
    assert s.world['revision']==w['revision']+1 and s.world['command_serial']==0
    assert s.db.execute('SELECT count(*) FROM receipts').fetchone()[0]==RECEIPT_LIMIT
    assert s.db.execute('SELECT count(*) FROM legacy_receipts').fetchone()[0]==count-RECEIPT_LIMIT
    before=s.snapshot();assert service.command(first)['payload']['receipt_retired']
    assert service.command(last[0])==last[1] and s.snapshot()==before
    s.close();compaction=compact(path)
    result={'legacy_receipts':count,'before_bytes':before_bytes,'startup_migration_ms':migration_ms,'retained_full_receipts':RECEIPT_LIMIT,'compact_retry_records':count-RECEIPT_LIMIT,'compaction':compaction,'scope':'Synthetic 50-person schema-7 save with 1200 legacy receipt snapshots; identities, clock, revision boundary and both old/recent retry paths verified.'}
    target=ROOT/'docs/previews/stage6d/legacy-migration.json';target.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
