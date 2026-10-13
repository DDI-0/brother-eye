"""Four real Godot launches with a temporary hungry civilian near the market."""
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from backend.store import Store
from backend.citizens import plan


def run():
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage3d-') as directory:
        directory = Path(directory)
        db, probe = directory/'world.sqlite3', directory/'probe.json'
        store = Store(db)
        store.world.update(clock_seconds=17940, paused=True, time_scale=60)
        c = store.world['citizens'][0]
        c['position'] = [18, .12, -12]
        c['needs']['hunger'] = 80
        plan(c, store.world['clock_seconds'])
        identity = c['id']
        store.commit('qa_fixture', {})
        store.close()
        for phase in ('write', 'read', 'journal', 'replay'):
            result = subprocess.run(['godot', '--headless', '--path', str(ROOT/'godot'),
                '--script', 'res://scripts/stage3d_check.gd', '--', '--with-simulation',
                f'--phase={phase}', f'--probe={probe}', f'--world-db={db}'],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
            print(result.stdout, end='', flush=True)
            if result.returncode or 'ERROR:' in result.stdout or 'FAIL ' in result.stdout:
                raise RuntimeError(f'{phase} acceptance failed')
            if phase == 'read':
                command_id = re.search(r'REPLAYED_COMMAND ([a-f0-9-]+)', result.stdout)[1]
                with sqlite3.connect(db) as connection:
                    assert connection.execute('SELECT COUNT(*) FROM receipts WHERE command_id=?', (command_id,)).fetchone()[0] == 1
                print('PASS crashed movement command has exactly one durable receipt')
            deadline = time.monotonic()+5
            while list(directory.glob('session-*.json')) and time.monotonic()<deadline:
                time.sleep(.05)
            assert not list(directory.glob('session-*.json')), 'App-owned backend did not stop'
            print('PASS app-owned backend stops after close', flush=True)
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
            world = json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            assert len(world['citizens']) == 34 and world['citizens'][0]['id'] == identity
            assert connection.execute("SELECT COUNT(*) FROM events WHERE kind='world_created'").fetchone()[0] == 1
        print('PASS 34 durable residents and one world across four launches; SQLite integrity ok')


if __name__ == '__main__':
    run()
