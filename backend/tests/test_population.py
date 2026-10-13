import copy
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import uuid
from backend.citizens import plan, validate_citizens
from backend.service import Service, envelope
from backend.store import Store


class PopulationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'world.sqlite3'
        self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
    def tearDown(self):self.store.close();self.temp.cleanup()
    def reports(self):
        return [{'citizen_id':c['id'],'goal_id':c['goal']['id'],'seq':c['motion_seq']+1,
                 'position':c['position'],'yaw':.4,'navigation':'TRAVELLING'} for c in self.store.world['citizens']]
    def command(self,reports,identifier=None):
        return self.service.command(envelope('set_population_progress',{'citizens':reports},identifier or str(uuid.uuid4())))
    def test_population_unique_and_local(self):
        people=self.store.world['citizens'];validate_citizens(people)
        self.assertEqual(len(people),34)
        self.assertEqual(sum(c['kind']=='police' for c in people),5)
        self.assertEqual(len({c['id'] for c in people}),34)
        self.assertEqual(len({tuple(c['position']) for c in people}),34)
        self.assertGreaterEqual(len({c['appearance'] for c in people}),9)
        for c in people:self.assertIn(c['goal']['place'],c['known_places'])
        police=people[29];plan(police,4200);self.assertEqual(police['goal']['place'],'patrol_b')
        plan(police,4800);self.assertEqual(police['goal']['place'],'patrol_c')
    def test_schema_two_preserves_alex_and_world(self):
        old=self.store.snapshot();old['citizens']=old['citizens'][:1]
        old['citizens'][0].pop('kind');old['citizens'][0].pop('appearance')
        old['citizens'][0]['needs']['energy']=9
        old['clock_seconds']=321;old['paused']=True
        self.store.db.execute('UPDATE world SET state_json=?',(json.dumps(old),))
        self.store.db.execute('PRAGMA user_version=2');self.store.db.commit();self.store.close()
        self.store=Store(self.path)
        for k,v in old.items():
            if k not in {'citizens','revision'}:self.assertEqual(self.store.world[k],v)
        self.assertEqual(self.store.world['revision'],old['revision']+1)
        for k,v in old['citizens'][0].items():self.assertEqual(self.store.world['citizens'][0][k],v)
        identities=[c['id'] for c in self.store.world['citizens']]
        self.store.close();self.store=Store(self.path)
        self.assertEqual(identities,[c['id'] for c in self.store.world['citizens']])
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM events WHERE kind='population_migrated'").fetchone()[0],1)
    def test_batch_atomicity_replay_and_validation(self):
        reports=self.reports();identifier=str(uuid.uuid4())
        first=self.command(reports,identifier);self.assertEqual(first,self.command(reports,identifier))
        self.assertTrue(all(c['motion_seq']==1 for c in self.store.world['citizens']))
        before=self.store.snapshot();bad=self.reports();bad[-1]['position']=[0,0,9999]
        with self.assertRaises(ValueError):self.command(bad)
        self.assertEqual(before,self.store.snapshot())
        with self.assertRaises(ValueError):self.command([reports[0],reports[0]])
        self.store.db.execute("CREATE TRIGGER fail_batch BEFORE INSERT ON receipts BEGIN SELECT RAISE(ABORT,'failure'); END")
        with self.assertRaises(sqlite3.IntegrityError):self.command(self.reports())
        self.assertEqual(before,self.store.snapshot())
    def test_full_population_restore_and_snapshot_size(self):
        self.command(self.reports());old=self.store.snapshot();self.store.close();self.store=Store(self.path)
        self.assertEqual(old,self.store.snapshot())
        self.assertLess(len(json.dumps(old)),2097152)
        self.assertLess(len(json.dumps({'citizens':self.reports()})),65536)
        bad=copy.deepcopy(old['citizens']);bad[-1]['id']=bad[0]['id']
        with self.assertRaises(ValueError):validate_citizens(bad)
