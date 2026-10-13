import asyncio
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import uuid

from backend.service import Service, decode, envelope
from backend.store import Store, WorldInUse
from websockets.asyncio.client import connect

ROOT = Path(__file__).resolve().parents[2]
VIEW = dict(position=[0, 0.3, 80], yaw=0.2, ground_pitch=-0.1,
            observer_position=[90, 140, 170], observer_rotation=[-0.3, 0.5, 0],
            flight_speed=42, observing=True)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'world.sqlite3'
        self.store = Store(self.path)
        self.service = Service(self.store, 'a'*64, os.getpid())

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def command(self, kind, payload):
        return envelope(kind, payload, str(uuid.uuid4()))

    def test_atomic_receipt_and_duplicate(self):
        request = self.command('set_explorer', VIEW)
        first = self.service.command(request)
        self.assertEqual(first, self.service.command(request))
        self.assertEqual(self.store.world['revision'], 1)
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0], 1)
        request['payload'] = {**VIEW, 'yaw': 1}
        with self.assertRaises(ValueError): self.service.command(request)
        self.assertEqual(self.store.world['explorer'], VIEW)

    def test_invalid_changes_leave_state_unchanged(self):
        before = self.store.snapshot()
        for payload in ({'paused': True, 'time_scale': True}, {'paused': 'yes', 'time_scale': 1}, {'paused': False, 'time_scale': 2}):
            with self.assertRaises(ValueError): self.service.command(self.command('set_clock', payload))
        for field, value in [('position', [0,0,1e9]), ('flight_speed', float('nan')), ('observing', 1)]:
            with self.assertRaises(ValueError): self.service.command(self.command('set_explorer', {**VIEW, field:value}))
        self.assertEqual(self.store.snapshot(), before)

    def test_transaction_failure_rolls_back_state_and_receipt(self):
        self.store.db.execute("CREATE TRIGGER fail_receipt BEFORE INSERT ON receipts BEGIN SELECT RAISE(ABORT, 'disk failure'); END")
        before = self.store.snapshot()
        with self.assertRaises(sqlite3.IntegrityError):
            self.service.command(self.command('set_clock', dict(paused=True, time_scale=10)))
        self.assertEqual(self.store.snapshot(), before)
        disk = json.loads(self.store.db.execute('SELECT state_json FROM world').fetchone()[0])
        self.assertEqual(disk, before)

    def test_single_writer_lock(self):
        with self.assertRaises(WorldInUse): Store(self.path)

    def test_wire_validation(self):
        for raw in ('[]', '{"v":2}', '{"v":true}', '{"v":1,"type":"save","id":"x","payload":{"x":NaN}}', b'hello'):
            with self.assertRaises(ValueError): decode(raw)

    def test_migration_and_restore(self):
        self.service.command(self.command('set_explorer', VIEW))
        world_id = self.store.world['world_id']
        self.store.close()
        self.store = Store(self.path)
        self.assertTrue(self.store.resumed)
        self.assertEqual(self.store.world['world_id'], world_id)
        self.assertEqual(self.store.world['explorer'], VIEW)
        self.assertEqual(self.store.db.execute('PRAGMA user_version').fetchone()[0], 8)
        self.assertEqual(self.store.db.execute('PRAGMA quick_check').fetchone()[0], 'ok')

    def test_future_and_corrupt_saves_preserved(self):
        for name in ('future', 'corrupt'):
            path = self.path.parent / name
            if name == 'future':
                db = sqlite3.connect(path)
                db.execute('PRAGMA user_version=999')
                db.close()
            else: path.write_bytes(b'This is not SQLite')
            before = path.read_bytes()
            with self.assertRaises((RuntimeError, sqlite3.DatabaseError)): Store(path)
            self.assertEqual(path.read_bytes(), before)


class ServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.path = self.directory/'world.sqlite3'
        self.ready = self.directory/'ready.json'
        self.processes = []
        self.sockets = []
        self.token = 'a'*64

    async def asyncTearDown(self):
        for socket in self.sockets: await socket.close()
        for proc in self.processes:
            if proc.poll() is None:
                proc.terminate()
                try: await asyncio.to_thread(proc.wait, 5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    await asyncio.to_thread(proc.wait)
        self.temp.cleanup()

    async def start(self, owner=None):
        self.ready.unlink(missing_ok=True)
        proc = subprocess.Popen([sys.executable, str(ROOT/'backend/service.py'), '--db',str(self.path), '--ready',str(self.ready), '--owner-pid',str(owner or os.getpid()), '--token',self.token], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.processes.append(proc)
        for _ in range(100):
            if self.ready.exists():
                ready = json.loads(self.ready.read_text())
                self.assertNotIn('error', ready, ready)
                return proc, ready
            await asyncio.sleep(.05)
        self.fail('Service startup timeout')

    async def client(self, ready):
        ws = await connect(f"ws://127.0.0.1:{ready['port']}", proxy=None)
        self.sockets.append(ws)
        await ws.send(json.dumps(envelope('hello', {'token':self.token},str(uuid.uuid4()))))
        welcome = json.loads(await asyncio.wait_for(ws.recv(), 3))
        self.assertEqual(welcome['type'], 'welcome')
        return ws, welcome['payload']['state']

    async def command(self, ws, kind, payload, request=None):
        request = request or envelope(kind,payload,str(uuid.uuid4()))
        await ws.send(json.dumps(request))
        while True:
            response = json.loads(await asyncio.wait_for(ws.recv(), 3))
            if response['type'] in ('ack', 'error'):
                return response

    async def test_restart_reconnect_and_no_offline_time(self):
        proc, ready = await self.start()
        ws, world = await self.client(ready)
        await asyncio.sleep(.35)
        running = await self.command(ws, 'save', {})
        self.assertGreater(running['payload']['state']['clock_seconds'], 0)
        await ws.close()
        await asyncio.sleep(.2)
        db = sqlite3.connect(self.path)
        frozen = json.loads(db.execute('SELECT state_json FROM world').fetchone()[0])['clock_seconds']
        db.close()
        await asyncio.sleep(.35)
        ws, state = await self.client(ready)
        self.assertEqual(state['clock_seconds'], frozen)
        self.assertEqual(state['world_id'], world['world_id'])
        await self.command(ws,'set_clock',dict(paused=True,time_scale=10))
        await self.command(ws,'set_explorer',VIEW)
        final = await self.command(ws,'shutdown',{})
        await asyncio.to_thread(proc.wait, 5)
        await asyncio.sleep(.3)
        proc, ready = await self.start()
        ws, state = await self.client(ready)
        self.assertEqual(state['world_id'],world['world_id'])
        self.assertEqual(state['explorer'],VIEW)
        self.assertEqual(state['clock_seconds'],final['payload']['state']['clock_seconds'])
        self.assertTrue(state['paused'])
        self.assertEqual(state['time_scale'],10)
        await self.command(ws,'shutdown',{})
        self.assertEqual(await asyncio.to_thread(proc.wait,5),0)

    async def test_crash_replay_and_reject_bad_wire(self):
        proc, ready = await self.start()
        ws, world = await self.client(ready)
        request = envelope('set_explorer',VIEW,str(uuid.uuid4()))
        ack = await self.command(ws,'set_explorer',VIEW,request)
        proc.kill()
        await asyncio.to_thread(proc.wait, 5)
        await ws.close()
        proc, ready = await self.start()
        ws, state = await self.client(ready)
        self.assertEqual(state['explorer'],VIEW)
        self.assertEqual(state['world_id'],world['world_id'])
        replay = await self.command(ws,'set_explorer',VIEW,request)
        self.assertEqual(replay,ack)
        await ws.send('{"v":2}')
        while True:
            error = json.loads(await asyncio.wait_for(ws.recv(),3))
            if error['type']=='error': break
        self.assertEqual(error['id'],'')
        changed = {**request, 'payload':{**VIEW,'yaw':2}}
        self.assertEqual((await self.command(ws,'set_explorer',VIEW,changed))['type'],'error')
        self.assertEqual((await self.command(ws,'save',{}))['payload']['state']['revision'],2)
        await self.command(ws,'shutdown',{})
        self.assertEqual(await asyncio.to_thread(proc.wait,5),0)

    async def test_intervention_ack_loss_backend_crash_and_replay(self):
        proc, ready = await self.start()
        ws, world = await self.client(ready)
        paused = await self.command(ws, 'set_clock', {'paused':True,'time_scale':1})
        world = paused['payload']['state']; c = world['citizens'][0]
        request = envelope('intervene', {'world_id':world['world_id'],'citizen_id':c['id'],
            'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,
            'action':'assign_destination','place':'food','reason':'ACK loss crash review'}, str(uuid.uuid4()))
        await ws.send(json.dumps(request))
        # Do not consume the ACK. Observe its durable transaction, then kill the process.
        for _ in range(100):
            with sqlite3.connect(self.path) as db:
                row = db.execute('SELECT response_json FROM receipts WHERE command_id=?',(request['id'],)).fetchone()
            if row: break
            await asyncio.sleep(.02)
        self.assertIsNotNone(row)
        expected = json.loads(row[0]); proc.kill(); await asyncio.to_thread(proc.wait,5); await ws.close()
        proc, ready = await self.start(); ws, restored = await self.client(ready)
        self.assertEqual(restored['citizens'][0]['intervention']['id'],request['id'])
        replay = await self.command(ws,'intervene',request['payload'],request)
        replay["payload"].pop("assessment",None)  # Derived wire projection is not part of a durable receipt.
        self.assertEqual(expected,replay)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM receipts WHERE command_id=?',(request['id'],)).fetchone()[0],1)
            data = [json.loads(row[0]) for row in db.execute("SELECT data_json FROM events WHERE kind='intervene'")]
            self.assertEqual(sum(e['command_id']==request['id'] and e['outcome']=='accepted' for row in data for e in row['interventions']),1)
        await self.command(ws,'shutdown',{})
        self.assertEqual(await asyncio.to_thread(proc.wait,5),0)

    async def test_owner_exit_stops_service(self):
        owner = subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'])
        self.processes.append(owner)
        proc, ready = await self.start(owner.pid)
        ws, _ = await self.client(ready)
        owner.terminate()
        await asyncio.to_thread(owner.wait,3)
        self.assertEqual(await asyncio.to_thread(proc.wait,5),0)
        self.assertFalse(self.ready.exists())


if __name__ == '__main__': unittest.main()
