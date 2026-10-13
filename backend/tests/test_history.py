import copy
import os
from pathlib import Path
import tempfile
import unittest
import uuid
from backend.service import Service, envelope
from backend.store import Store


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.store=Store(Path(self.temp.name)/'world.sqlite3')
        self.service=Service(self.store,'a'*64,os.getpid())
    def tearDown(self):self.store.close();self.temp.cleanup()
    def assign(self, index=0):
        world=self.store.world;c=world['citizens'][index];active=c['intervention']
        return self.service.command(envelope('intervene',{'world_id':world['world_id'],'citizen_id':c['id'],
            'expected_goal_id':c['goal']['id'],'expected_intervention_id':active['id'] if active else None,
            'action':'assign_destination','place':'food','reason':'History acceptance'},str(uuid.uuid4())))
    def query(self, **updates):
        payload={'citizen_id':'','before_seq':0,'before_index':0,'limit':25,**updates}
        return self.service.command(envelope('query_interventions',payload,str(uuid.uuid4())))['payload']
    def test_pagination_reaches_beyond_recent_cache_without_duplicates(self):
        for _ in range(70):self.assign()
        self.assertEqual(len(self.store.world['intervention_history']),64)
        all_entries=[];cursor={}
        while True:
            page=self.query(**cursor);all_entries.extend(page['entries'])
            if not page['has_more']:break
            cursor=page['next_cursor']
        self.assertEqual(len(all_entries),139)
        self.assertEqual(len({event['id'] for event in all_entries}),139)
        order=[(e['event_seq'],e['event_index']) for e in all_entries]
        self.assertEqual(order,sorted(order,reverse=True))
        self.assertEqual(self.query(**page['next_cursor'])['entries'],[])
    def test_read_only_filter_cursor_and_concurrent_newer_events(self):
        self.assign();self.assign();self.assign(1)
        before=self.store.snapshot();count=self.store.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0]
        events=self.store.db.execute('SELECT COUNT(*) FROM events').fetchone()[0]
        page=self.query(citizen_id=before['citizens'][0]['id'],limit=1.0)
        self.assertEqual(len(page['entries']),1);self.assertTrue(page['has_more'])
        self.assertEqual(before,self.store.snapshot())
        self.assertEqual(count,self.store.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0])
        self.assertEqual(events,self.store.db.execute('SELECT COUNT(*) FROM events').fetchone()[0])
        self.assign()
        older=self.query(citizen_id=before['citizens'][0]['id'],**page['next_cursor'])
        self.assertEqual(len(older['entries']),2)
        self.assertEqual({e['citizen_id'] for e in older['entries']},{before['citizens'][0]['id']})
        self.assertEqual(self.query(citizen_id='absent')['entries'],[])
    def test_invalid_queries_leave_world_and_receipts_unchanged(self):
        before=self.store.snapshot()
        for update in [{'limit':0},{'limit':51},{'limit':True},{'before_seq':-1},{'before_seq':1.5},
                       {'before_index':float('nan')},{'citizen_id':[]},{'extra':'invalid'}]:
            with self.assertRaises(ValueError):self.query(**update)
        self.assertEqual(before,self.store.snapshot())
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0],0)
