import copy
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import uuid
from backend.exceptional import PROFILES
from backend.citizens import advance_citizens
from backend.service import Service, envelope
from backend.store import Store, validate_world


class ExceptionalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)/'world.sqlite3'
        self.store = Store(self.path)
        self.service = Service(self.store, 'a'*64, os.getpid())
    def tearDown(self):
        self.store.close()
        self.temp.cleanup()
    def request(self, c, **updates):
        return envelope('intervene', {'world_id': self.store.world['world_id'], 'citizen_id': c['id'],
            'expected_goal_id': c['goal']['id'], 'expected_intervention_id': c['intervention']['id'] if c['intervention'] else None,
            'action': 'assign_destination', 'place': 'food', 'reason': 'Foundation acceptance', **updates}, str(uuid.uuid4()))
    def legacy(self):
        self.store.world['citizens'] = self.store.world['citizens'][:30]
        self.store.world.update(paused=True, clock_seconds=321., tick=57)
        request = self.request(self.store.world['citizens'][0])
        response = self.service.command(request)
        self.store.db.execute('PRAGMA user_version=4');self.store.db.commit()
        return request, response, self.store.snapshot()
    def test_catalogue_and_directed_companion(self):
        world = self.store.snapshot();validate_world(world)
        self.assertEqual(len(world['citizens']),34)
        agents = world['citizens'][30:]
        self.assertEqual([c['exceptional']['profile'] for c in agents],[p['key'] for p in PROFILES])
        for c in agents:
            self.assertEqual(c['exceptional']['behavior_stage'],__import__('backend.agent_policies',fromlist=['STAGES']).STAGES[c['exceptional']['profile']])
            self.assertEqual(c['exceptional']['observations'],[])
            self.assertIsNone(c['exceptional']['project'])
        self.assertEqual(agents[-1]['exceptional']['relationships'],{world['citizens'][1]['id']:{'trust':25,'companion':True}})
        self.assertNotIn('exceptional',world['citizens'][1])
    def test_schema_four_preserves_original_people_and_receipts(self):
        request, response, old = self.legacy()
        receipt_bytes = self.store.db.execute('SELECT request_json,response_json FROM receipts').fetchall()
        self.store.close();self.store = Store(self.path)
        self.service = Service(self.store,'a'*64,os.getpid())
        self.assertEqual(self.store.world['citizens'][:30],old['citizens'])
        for key in old:
            if key not in {'citizens','revision'}:self.assertEqual(self.store.world[key],old[key])
        self.assertEqual(self.store.world['revision'],old['revision']+1)
        self.assertEqual(self.service.command(request),response)
        self.assertEqual(len(response['payload']['state']['citizens']),30)
        self.assertLess(response['payload']['state']['revision'],self.store.world['revision'])
        self.assertEqual(receipt_bytes,self.store.db.execute('SELECT request_json,response_json FROM receipts').fetchall())
        saved = self.store.snapshot();self.store.close();self.store=Store(self.path)
        self.assertEqual(saved,self.store.snapshot())
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM events WHERE kind='exceptional_agents_migrated'").fetchone()[0],1)
    def test_failed_migration_is_atomic(self):
        _, _, old = self.legacy()
        self.store.db.execute("CREATE TRIGGER fail_migration BEFORE INSERT ON events WHEN NEW.kind='exceptional_agents_migrated' BEGIN SELECT RAISE(ABORT,'migration failure'); END")
        self.store.db.commit();self.store.close()
        with self.assertRaises(sqlite3.IntegrityError):Store(self.path)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],4)
            self.assertEqual(json.loads(db.execute('SELECT state_json FROM world').fetchone()[0]),old)
            db.execute('DROP TRIGGER fail_migration')
        self.store=Store(self.path)
        self.assertEqual(len(self.store.world['citizens']),34)
    def test_core_identity_and_bounded_state_validation(self):
        original = self.store.snapshot()
        changes = [('core','new ideology'),('profile','unknown'),('profile_version',2),('behavior_stage','autonomous_ai'),
                   ('observations',[{'invented':True}]),('project',{}),
                   ('relationships',{'unknown':{'trust':0,'companion':False}})]
        for field, value in changes:
            with self.subTest(field=field):
                world=copy.deepcopy(original);world['citizens'][30]['exceptional'][field]=value
                with self.assertRaises(ValueError):validate_world(world)
        for field,value in [('name','replacement'),('id',str(uuid.uuid4())),('appearance',3)]:
            world=copy.deepcopy(original);world['citizens'][30][field]=value
            with self.assertRaises(ValueError):validate_world(world)
    def test_override_release_cannot_edit_core_or_relationships(self):
        for index in range(30,34):
            c=self.store.world['citizens'][index];core=copy.deepcopy(c['exceptional'])
            request=self.request(c)
            response=self.service.command(request)
            self.assertEqual(response['payload']['intervention']['outcome'],'accepted')
            self.assertEqual(response,self.service.command(request))
            self.store.world['citizens'][index]['needs']['energy']=0
            advance_citizens(self.store.world,1)
            c=self.store.world['citizens'][index]
            self.assertEqual(c['goal']['place'],'food');self.assertEqual(c['exceptional'],core)
            rejected=self.service.command(self.request(c,core='changed'))
            self.assertEqual(rejected['payload']['intervention']['outcome'],'rejected')
            self.service.command(self.request(c,action='release',place=None))
            c=self.store.world['citizens'][index]
            self.assertIsNone(c['intervention']);self.assertEqual(c['goal']['place'],'home')
            self.assertEqual(c['exceptional'],core)
        validate_world(self.store.world)
