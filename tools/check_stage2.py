"""Launch the real app against a temporary save; never touches runtime/."""
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run():
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage2-') as directory:
        directory = Path(directory)
        db = directory/'world.sqlite3'
        probe = directory/'probe.json'
        for phase in ('write','read','ground','journal','replay'):
            result = subprocess.run(['godot','--headless','--path',str(ROOT/'godot'),
                '--script','res://scripts/stage2_check.gd','--','--stage2-qa',
                f'--phase={phase}',f'--probe={probe}',f'--world-db={db}'],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
            print(result.stdout, end='')
            if result.returncode or 'ERROR:' in result.stdout or 'FAIL ' in result.stdout:
                raise RuntimeError(f'{phase} acceptance failed')
            if phase == 'read':
                request_id = re.search(r'REPLAYED_COMMAND ([a-f0-9-]+)',result.stdout)[1]
                with sqlite3.connect(db) as connection:
                    count = connection.execute('SELECT COUNT(*) FROM receipts WHERE command_id=?',(request_id,)).fetchone()[0]
                    assert count == 1, 'Queued command applied more than once'
                    print('PASS crash replay has exactly one durable receipt')
            # Ready file is removed only after the service releases its save lock.
            deadline = time.monotonic()+5
            while list(directory.glob('session-*.json')) and time.monotonic()<deadline:
                time.sleep(.05)
            assert not list(directory.glob('session-*.json')), 'Backend did not stop on app close'
            print('PASS app-owned backend stops after close')
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
            assert connection.execute("SELECT COUNT(*) FROM events WHERE kind='world_created'").fetchone()[0] == 1
        print('PASS one world created across five launches; SQLite integrity ok')


if __name__ == '__main__': run()
