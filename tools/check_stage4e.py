"""Combined Stage 4 acceptance. Never opens the normal city save."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from backend.store import Store
from backend.citizens import plan


def run(native=False, evidence_dir=None):
    with tempfile.TemporaryDirectory(prefix='brother-eye-stage4e-') as name:
        folder = Path(name)
        db, probe = folder/'world.sqlite3', folder/'probe.json'
        store = Store(db)
        store.world.update(paused=True, time_scale=1)
        c = store.world['citizens'][0]
        c['position'] = [18, .12, -8]
        c['needs']['hunger'] = 92
        plan(c, 0)
        store.commit('qa_fixture', {})
        store.close()
        for phase in ('write', 'read'):
            command = ['godot'] + ([] if native else ['--headless']) + [
                '--path', str(ROOT/'godot'), '--script', 'res://scripts/stage4e_check.gd', '--',
                '--with-simulation', f'--world-db={db}', f'--phase={phase}', f'--probe={probe}']
            if native:
                command.append('--capture-stage4e')
            try:
                result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=150)
            except subprocess.TimeoutExpired as error:
                print(error.stdout, flush=True)
                raise
            print(result.stdout, end='', flush=True)
            assert result.returncode == 0 and f'STAGE4E_CHECK {phase} failures=0' in result.stdout
            assert 'ERROR:' not in result.stdout and 'FAIL ' not in result.stdout
            end = time.monotonic()+8
            while list(folder.glob('session-*.json')) and time.monotonic() < end:
                time.sleep(.05)
            assert not list(folder.glob('session-*.json')), 'Owned backend did not stop'
        with sqlite3.connect(db) as connection:
            assert connection.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
            assert connection.execute("SELECT COUNT(*) FROM events WHERE kind='world_created'").fetchone()[0] == 1
            world = json.loads(connection.execute('SELECT state_json FROM world').fetchone()[0])
            assert len(world['citizens']) == 34
            assert connection.execute("SELECT COUNT(*) FROM receipts WHERE json_extract(request_json,'$.type')='intervene'").fetchone()[0] == 2
            events = [json.loads(row[0]) for row in connection.execute('SELECT data_json FROM events')]
            audit = [event for data in events for event in data.get('interventions', [])]
            for outcome in ('accepted', 'rejected', 'waiting_for_route', 'completed'):
                assert any(event['outcome'] == outcome for event in audit), outcome
            trace = {'world_id': world['world_id'], 'citizen_id': world['citizens'][0]['id'],
                     'clock_seconds': world['clock_seconds'], 'interventions': audit,
                     'integrity': 'ok', 'population': len(world['citizens'])}
            label = 'native' if native else 'headless'
            ((evidence_dir or ROOT/'docs/previews/stage4e')/f'trace-{label}.json').write_text(json.dumps(trace, indent=2)+'\n')
        print('PASS durable accepted/rejected/wait/completion trace, exactly two intervention receipts, one world and 34 residents')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--evidence-dir', type=Path)
    args = parser.parse_args()
    if args.evidence_dir:
        args.evidence_dir.mkdir(parents=True, exist_ok=True)
    run(args.native, args.evidence_dir)
