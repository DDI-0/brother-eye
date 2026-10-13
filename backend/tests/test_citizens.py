import copy
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import uuid
from backend.citizens import advance_citizens, plan, progress, validate_citizens
from backend.service import Service, envelope
from backend.store import Store


class CitizenTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'world.sqlite3'
        self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
    def tearDown(self):self.store.close();self.temp.cleanup()
    @property
    def c(self):return self.store.world['citizens'][0]
    def report(self, **changes):
        c=self.c
        return {'citizen_id':c['id'],'goal_id':c['goal']['id'],'seq':c['motion_seq']+1,
                'position':list(c['position']),'yaw':0.3,'navigation':'TRAVELLING',**changes}
    def command(self,payload,request_id=None):
        return self.service.command(envelope('set_citizen_progress',payload,request_id or str(uuid.uuid4())))
    def arrive(self):self.command(self.report(position=self.c['goal']['position'],navigation='ARRIVED'))
    def test_schedule_and_identity(self):
        identity=self.c['id'];self.assertEqual(self.c['goal']['place'],'work')
        for hour,place in [(12,'food'),(13,'work'),(17,'park'),(19,'home'),(32,'work')]:
            self.store.world['clock_seconds']=(hour-8)*3600;plan(self.c,self.store.world['clock_seconds'])
            self.assertEqual(self.c['goal']['place'],place)
        self.assertEqual(identity,self.c['id'])
    def test_needs_only_recover_after_physical_arrival(self):
        hunger=self.c['needs']['hunger'];advance_citizens(self.store.world,60)
        self.assertGreater(self.c['needs']['hunger'],hunger)
        self.c['needs']['hunger']=85;plan(self.c,60)
        self.assertEqual(self.c['goal']['place'],'food')
        advance_citizens(self.store.world,60)
        self.assertGreater(self.c['needs']['hunger'],85)
        self.arrive();self.assertEqual(self.c['activity'],'eating')
        advance_citizens(self.store.world,120)
        self.assertLess(self.c['needs']['hunger'],85)
        self.assertEqual(self.c['goal']['place'],'food') # hysteresis, not switching every tick
    def test_priority_recovery_and_bounded_memory(self):
        self.c['needs']['energy']=10;plan(self.c,0);self.assertEqual(self.c['goal']['place'],'home')
        self.arrive();advance_citizens(self.store.world,3600)
        self.assertEqual(self.c['needs']['energy'],100)
        self.assertEqual(self.c['goal']['place'],'work')
        for i in range(40):
            self.store.world['clock_seconds']=(4 if i%2 else 5)*3600
            plan(self.c,self.store.world['clock_seconds'])
        self.assertEqual(len(self.c['memory']),16)
        validate_citizens(self.store.world['citizens'])
    def test_duplicate_stale_and_invalid_progress(self):
        request_id=str(uuid.uuid4());payload=self.report(position=[18,.12,88])
        first=self.command(payload,request_id);self.assertEqual(first,self.command(payload,request_id))
        self.assertEqual(self.c['motion_seq'],1)
        self.command(self.report(seq=1,position=[18,.12,86]));self.assertEqual(self.c['position'],[18,.12,88])
        old_goal=self.c['goal']['id'];self.c['needs']['hunger']=90;plan(self.c,0)
        self.command(self.report(goal_id=old_goal,position=[18,.12,84]));self.assertEqual(self.c['position'],[18,.12,88])
        for changes in [{'position':[0,0,9999]},{'position':[0,0,float('nan')]},{'seq':True},{'navigation':'ARRIVED'},{'citizen_id':str(uuid.uuid4())}]:
            before=self.store.snapshot()
            with self.assertRaises(ValueError):self.command(self.report(**changes))
            self.assertEqual(before,self.store.snapshot())
    def test_progress_receipt_failure_rolls_back_citizen(self):
        before=self.store.snapshot()
        self.store.db.execute("CREATE TRIGGER fail_progress BEFORE INSERT ON receipts BEGIN SELECT RAISE(ABORT,'failure'); END")
        with self.assertRaises(sqlite3.IntegrityError):self.command(self.report(position=[18,.12,89]))
        self.assertEqual(before,self.store.snapshot())
        self.assertEqual(before,json.loads(self.store.db.execute('SELECT state_json FROM world').fetchone()[0]))
    def test_integral_json_journal_sequence(self):
        self.command(self.report(seq=1.0))
        self.assertEqual(self.c['motion_seq'],1)
        self.assertIs(type(self.c['motion_seq']),int)
        for seq in [1.5, float('inf'), 2**53, False]:
            with self.assertRaises(ValueError):self.command(self.report(seq=seq))
    def test_restoration_preserves_routine_and_no_offline_time(self):
        self.arrive();advance_citizens(self.store.world,50);self.store.commit('checkpoint',{})
        expected=self.store.snapshot();self.store.close();self.store=Store(self.path)
        self.assertEqual(expected['citizens'],self.store.world['citizens'])
        self.assertEqual(expected['clock_seconds'],self.store.world['clock_seconds'])
    def test_version_one_migration_preserves_existing_city(self):
        old=self.store.snapshot();old.pop('citizens');old['clock_seconds']=9876;old['revision']=42
        self.store.db.execute('UPDATE world SET state_json=?',(json.dumps(old),));self.store.db.execute('PRAGMA user_version=1');self.store.db.commit()
        self.store.close();self.store=Store(self.path)
        self.assertEqual({k:self.store.world[k] for k in old if k!='revision'},{k:v for k,v in old.items() if k!='revision'})
        self.assertEqual(self.store.world['revision'],old['revision']+1)
        self.assertEqual(self.store.db.execute('PRAGMA user_version').fetchone()[0],8)
        self.assertEqual(len(self.store.world['citizens']),34)
        identity=self.c['id'];self.store.close();self.store=Store(self.path)
        self.assertEqual(identity,self.c['id'])
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM events WHERE kind='citizens_migrated'").fetchone()[0],1)
