"""Offline hot-database compaction. Close Brother Eye first; never resets a world."""
import argparse
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from backend.store import Store,validate_world
from backend.retention import prune,status

def compact(path):
    if not path.is_file():raise ValueError('Choose an existing database; compaction does not create worlds.')
    before_size=path.stat().st_size
    store=Store(path) # Enforces the same exclusive application lock.
    try:
        before=store.snapshot()
        with store.db:result=prune(store.db)
        store.db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        store.db.execute('VACUUM')
        store.db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        assert store.snapshot()==before
        validate_world(store.world)
        assert store.db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
        result.update(before_bytes=before_size,after_bytes=path.stat().st_size,retention=status(store.db))
        return result
    finally:store.close()
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--db',type=Path,required=True)
    print(json.dumps(compact(parser.parse_args().db),indent=2))
