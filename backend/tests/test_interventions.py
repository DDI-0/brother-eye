import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import uuid
from backend.citizens import advance_citizens
from backend.service import Service, envelope
from backend.store import Store, validate_world


class InterventionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)/'world.sqlite3'
        self.store = Store(self.path)
        self.service = Service(self.store, 'a'*64, os.getpid())
    def tearDown(self):
        self.store.close(); self.temp.cleanup()
    @property
    def c(self): return self.store.world['citizens'][0]
    def request(self, **updates):
        return envelope('intervene', {'world_id': self.store.world['world_id'], 'citizen_id': self.c['id'],
            'expected_goal_id': self.c['goal']['id'], 'expected_intervention_id': self.c['intervention']['id'] if self.c['intervention'] else None,
            'action': 'assign_destination', 'place': 'food', 'reason': 'Review market access', **updates}, str(uuid.uuid4()))
    def send(self, **updates): return self.service.command(self.request(**updates))['payload']['intervention']
    def report(self, **updates):
        c = self.c
        payload = {'citizen_id':c['id'], 'goal_id':c['goal']['id'], 'seq':c['motion_seq']+1,
                   'position':list(c['position']), 'yaw':0, 'navigation':'TRAVELLING', **updates}
        return self.service.command(envelope('set_citizen_progress',payload,str(uuid.uuid4())))
    def test_override_precedence_arrival_release_and_pause(self):
        self.store.world['paused'] = True
        pos = list(self.c['position']); needs = dict(self.c['needs'])
        self.assertEqual(self.send()['outcome'],'accepted')
        self.assertEqual(self.c['position'],pos); self.assertEqual(self.c['needs'],needs)
        self.assertEqual(self.c['activity'],'travelling')
        self.c['needs']['energy'] = 0
        advance_citizens(self.store.world,100)
        self.assertEqual(self.c['goal']['place'],'food')
        self.report(position=self.c['goal']['position'],navigation='ARRIVED')
        self.assertEqual(self.c['intervention']['status'],'completed')
        advance_citizens(self.store.world,100)
        self.assertEqual(self.c['goal']['reason'],'intervention')
        self.assertEqual(self.send(action='release',place=None)['outcome'],'accepted')
        self.assertIsNone(self.c['intervention']); self.assertEqual(self.c['goal']['place'],'home')
        validate_world(self.store.world)
    def test_rejections_are_durable_without_resident_changes(self):
        cases = [{'citizen_id':'unknown'},{'place':'secret'},{'action':'edit_memory'},{'reason':''},
                 {'reason':'a'*241},{'reason':'line\nbreak'},{'world_id':str(uuid.uuid4())},
                 {'expected_goal_id':str(uuid.uuid4())},{'expected_intervention_id':str(uuid.uuid4())},{'action':'release','place':None},{'place':[]}, {'extra':True}]
        for updates in cases:
            before = self.store.snapshot()['citizens']; request = self.request(**updates)
            response = self.service.command(request)
            self.assertEqual(response['payload']['intervention']['outcome'],'rejected')
            self.assertEqual(before,self.store.world['citizens'])
            self.assertEqual(response,self.service.command(request))
            self.assertEqual(self.store.world['intervention_history'][-1]['outcome'],'rejected')
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0],len(cases))
    def test_replace_stale_goal_release_and_wait(self):
        first = self.request(); self.service.command(first); old_goal = self.c['goal']['id']
        stale = self.request(place='home')
        self.send(place='park'); current = self.c['goal']['id']
        self.assertNotEqual(current,old_goal)
        self.assertEqual(self.service.command(stale)['payload']['intervention']['outcome'],'rejected')
        self.report(goal_id=old_goal,position=[18,.12,-14],navigation='ARRIVED')
        self.assertEqual(self.c['goal']['id'],current); self.assertEqual(self.c['intervention']['status'],'travelling')
        self.report(navigation='WAITING FOR ROUTE')
        self.assertEqual(self.c['intervention']['status'],'waiting_for_route')
        self.report(navigation='WAITING FOR SPACE')
        self.assertEqual(self.c['intervention']['status'],'waiting_for_space')
        self.report(); self.assertEqual(self.c['intervention']['status'],'travelling')
        self.assertEqual(self.send(action='release',place=None)['outcome'],'accepted')
        self.report(goal_id=current,position=[10,.12,-40],navigation='ARRIVED')
        self.assertNotEqual(self.c['goal']['id'],current)
    def test_receipt_replay_restart_and_changed_payload(self):
        request = self.request(); response = self.service.command(request)
        goal = self.c['goal']['id']; history = self.store.snapshot()['intervention_history']
        self.store.close(); self.store = Store(self.path); self.service = Service(self.store,'a'*64,os.getpid())
        self.assertEqual(self.c['goal']['id'],goal); self.assertEqual(self.store.world['intervention_history'],history)
        self.assertEqual(response,self.service.command(request))
        request['payload']['place'] = 'home'
        with self.assertRaises(ValueError): self.service.command(request)
        self.assertEqual(self.c['goal']['id'],goal)
    def test_transaction_failure_rolls_back_all_audit_and_state(self):
        before = self.store.snapshot()
        count = self.store.db.execute('SELECT COUNT(*) FROM events').fetchone()[0]
        self.store.db.execute("CREATE TRIGGER fail_receipt BEFORE INSERT ON receipts BEGIN SELECT RAISE(ABORT,'failure'); END")
        with self.assertRaises(sqlite3.IntegrityError): self.send()
        self.assertEqual(self.store.snapshot(),before)
        self.assertEqual(json.loads(self.store.db.execute('SELECT state_json FROM world').fetchone()[0]),before)
        self.assertEqual(count,self.store.db.execute('SELECT COUNT(*) FROM events').fetchone()[0])
    def test_police_local_knowledge_and_repeat_destination_goal_identity(self):
        officer = self.store.world['citizens'][29]
        request = self.request(citizen_id=officer['id'], expected_goal_id=officer['goal']['id'], place='patrol_a')
        self.assertEqual(self.service.command(request)['payload']['intervention']['outcome'],'accepted')
        self.assertEqual(officer['goal']['reason'],'schedule')  # Detached apply does not mutate caller-held records.
        officer = self.store.world['citizens'][29]
        self.assertEqual(officer['goal']['place'],'patrol_a')
        self.assertEqual(self.send(place='patrol_a')['outcome'],'rejected')  # Alex does not know patrol stops.
        self.send(); old_goal = self.c['goal']['id']
        self.send(); self.assertNotEqual(old_goal,self.c['goal']['id'])
        validate_world(self.store.world)

    def test_schema_three_migration_preserves_people_and_city(self):
        old = self.store.snapshot(); old['citizens']=old['citizens'][:30];old.pop('intervention_history')
        for c in old['citizens']: c.pop('intervention')
        self.store.db.execute('UPDATE world SET state_json=?',(json.dumps(old),))
        self.store.db.execute('PRAGMA user_version=3'); self.store.db.commit(); self.store.close()
        self.store = Store(self.path)
        actual = self.store.snapshot(); self.assertEqual(actual.pop('intervention_history'),[])
        actual['citizens']=actual['citizens'][:30]
        for c in actual['citizens']: self.assertIsNone(c.pop('intervention'))
        self.assertEqual(actual['revision'],old['revision']+1);actual['revision']=old['revision']
        self.assertEqual(actual,old)
        self.assertEqual(self.store.db.execute('PRAGMA user_version').fetchone()[0],8)
        validate_world(self.store.world)
    def test_history_bounded_sql_audit_complete_and_arrival_not_faked(self):
        for _ in range(70): self.send()
        self.assertEqual(len(self.store.world['intervention_history']),64)
        rows = self.store.db.execute("SELECT data_json FROM events WHERE kind='intervene'").fetchall()
        self.assertEqual(len(rows),70)
        self.assertEqual(len(json.loads(rows[-1][0])['interventions']),2)
        before = self.store.snapshot()
        with self.assertRaises(ValueError): self.report(navigation='ARRIVED')
        self.assertEqual(before,self.store.snapshot())
