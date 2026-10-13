"""Retention must bound hot data without replaying old commands or losing state."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import uuid
from backend.retention import command_id,prune,RetiredCommand,RECEIPT_LIMIT,RECENT_EVENTS,SIGNIFICANT_EVENTS,PRUNE_INTERVAL
from backend.service import Service,envelope
from backend.store import Store,validate_world
from backend.history import query

class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'world.sqlite3';self.store=Store(self.path)
        self.store.world['paused']=True;self.service=Service(self.store,'a'*64,os.getpid())
    def tearDown(self):self.store.close();self.temp.cleanup()
    def request(self,kind='save',payload=None):
        serial=self.store.world['command_serial']+1
        return {**envelope(kind,payload or {},command_id(self.store.world['world_id'],serial)),'serial':serial}
    def commit_many(self,n):
        for _ in range(n):self.service.command(self.request())
    def assign(self):
        w=self.store.world;c=w['citizens'][0]
        return self.request('intervene',{'world_id':w['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':c['intervention']['id'] if c['intervention'] else None,'action':'assign_destination','place':'food','reason':'Retention acceptance'})
    def test_recent_retries_exact_old_serials_retire_and_ids_cannot_be_reused(self):
        first=self.request('set_clock',{'paused':True,'time_scale':10});response=self.service.command(first)
        self.assertEqual(self.service.command(first),response)
        self.commit_many(RECEIPT_LIMIT+PRUNE_INTERVAL)
        before=self.store.snapshot()
        with self.assertRaises(RetiredCommand):self.service.command(first)
        with self.assertRaises(ValueError):self.service.command({**first,'serial':before['command_serial']+1})
        self.assertEqual(self.store.snapshot(),before)
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM legacy_receipts').fetchone()[0],0)
        self.assertLessEqual(self.store.db.execute('SELECT count(*) FROM receipts').fetchone()[0],RECEIPT_LIMIT+PRUNE_INTERVAL-1)
    def test_legacy_compaction_retains_digest_result_and_never_reapplies(self):
        old=self.assign();old.pop('serial');old['id']=str(uuid.uuid4());response=self.service.command(old)
        self.commit_many(RECEIPT_LIMIT+PRUNE_INTERVAL)
        before=self.store.snapshot();replay=self.service.command(old)
        self.assertEqual(replay['payload']['intervention'],response['payload']['intervention'])
        self.assertTrue(replay['payload']['receipt_retired']);self.assertEqual(before,replay['payload']['state'])
        with self.assertRaises(ValueError):self.service.command({**old,'payload':{**old['payload'],'place':'home'}})
        self.assertEqual(self.store.snapshot(),before)
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM legacy_receipts').fetchone()[0],1)
    def test_pruning_is_in_the_receipt_transaction_and_rolls_back(self):
        self.commit_many(RECEIPT_LIMIT+5)
        self.store.commits_since_prune=PRUNE_INTERVAL-1
        self.store.db.execute("CREATE TRIGGER fail_prune BEFORE DELETE ON receipts BEGIN SELECT RAISE(ABORT,'injected'); END")
        before=self.store.snapshot();count=self.store.db.execute('SELECT count(*) FROM receipts').fetchone()[0]
        request=self.request()
        with self.assertRaises(sqlite3.IntegrityError):self.service.command(request)
        self.assertEqual(self.store.snapshot(),before)
        self.assertEqual(json.loads(self.store.db.execute('SELECT state_json FROM world').fetchone()[0]),before)
        self.assertEqual(count,self.store.db.execute('SELECT count(*) FROM receipts').fetchone()[0])
        self.assertIsNone(self.store.receipt(request['id'],request))
    def test_future_gap_invalid_serial_and_identity_rejected_without_mutation(self):
        before=self.store.snapshot()
        for serial in (None,0,-1,True,1.5,2**53,3):
            request={**envelope('save',{},str(uuid.uuid4())),'serial':serial}
            if type(serial) is int and serial>0:request['id']=command_id(before['world_id'],serial)
            with self.assertRaises(ValueError):self.service.command(request)
        self.assertEqual(before,self.store.snapshot())
    def test_recent_receipt_rejects_boolean_numeric_payload_substitution(self):
        request=self.request('set_clock',{'paused':True,'time_scale':1})
        self.service.command(request);before=self.store.snapshot()
        changed=copy.deepcopy(request);changed['payload']['time_scale']=True
        with self.assertRaises(ValueError):self.service.command(changed)
        self.assertEqual(before,self.store.snapshot())
    def test_window_metadata_cursor_monotonic_and_no_world_change(self):
        first=self.assign();self.service.command(first)
        initial=query(self.store,{'citizen_id':'','before_seq':0,'before_index':0,'limit':1})
        for _ in range(SIGNIFICANT_EVENTS+40):self.service.command(self.assign())
        with self.store.db:prune(self.store.db)
        before=self.store.snapshot()
        page=query(self.store,{'citizen_id':'','before_seq':0,'before_index':0,'limit':50})
        self.assertGreater(page['retention']['pruned_audit_entries'],0)
        self.assertGreater(page['entries'][0]['event_seq'],initial['entries'][0]['event_seq'])
        retired_page=query(self.store,{'citizen_id':'',**initial['next_cursor'],'limit':25})
        self.assertEqual(retired_page['entries'],[])
        self.assertEqual(before,self.store.snapshot())
        self.assertLessEqual(self.store.db.execute('SELECT count(*) FROM events').fetchone()[0],RECENT_EVENTS+SIGNIFICANT_EVENTS+10)
        self.assertEqual(self.store.db.execute("SELECT count(*) FROM events WHERE kind='world_created'").fetchone()[0],1)
    def test_restore_preserves_watermark_state_and_recent_receipt(self):
        self.commit_many(RECEIPT_LIMIT+10);last=self.request();response=self.service.command(last)
        before=self.store.snapshot();self.store.close();self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
        self.assertEqual(before,self.store.snapshot());self.assertEqual(response,self.service.command(last))
        next_request=self.request();self.service.command(next_request)
        self.assertEqual(self.store.world['command_serial'],before['command_serial']+1);validate_world(self.store.world)
    def test_schema_seven_upgrade_is_atomic_and_preserves_receipts(self):
        old=envelope('save',{},str(uuid.uuid4()));response=self.service.command(old)
        self.store.world.pop('command_serial');self.store.commit('legacy_fixture',{})
        before=self.store.snapshot();self.store.db.execute('PRAGMA user_version=7');self.store.db.commit();self.store.close()
        with sqlite3.connect(self.path) as db:
            db.execute('DROP TABLE legacy_receipts');db.execute('DROP TABLE retention')
            db.execute('DROP INDEX receipt_order');db.execute('ALTER TABLE receipts DROP COLUMN committed_seq')
            db.execute("CREATE TRIGGER fail_retention BEFORE INSERT ON events WHEN NEW.kind='retention_migrated' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(sqlite3.IntegrityError):Store(self.path)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],7)
            self.assertEqual(json.loads(db.execute('SELECT state_json FROM world').fetchone()[0]),before)
            db.execute('DROP TRIGGER fail_retention')
        self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
        self.assertEqual(self.store.world['revision'],before['revision']+1)
        self.assertEqual(self.store.world['citizens'],before['citizens'])
        self.assertEqual(self.service.command(old),response)
        self.assertEqual(self.store.db.execute('PRAGMA user_version').fetchone()[0],8)
