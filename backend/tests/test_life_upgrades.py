"""Atomic life/population upgrades preserve live goals and historical receipts."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
import uuid
from backend.store import Store,validate_world
from backend.service import Service,envelope
from backend import agent_behavior as behavior,agent_policies as policies

class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'world.sqlite3'
    def tearDown(self):self.temp.cleanup()
    def legacy(self):
        store=Store(self.path);world=store.world;world['paused']=True
        c=world['citizens'][0]
        cmd=envelope('intervene',{'world_id':world['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,'action':'assign_destination','place':'food','reason':'Upgrade preservation'},str(uuid.uuid4()))
        response=Service(store,'a'*64,os.getpid()).command(cmd)
        world=store.world;world.pop('life_version');store.commit('legacy_fixture',{})
        before=store.snapshot();store.close();return before,cmd,response
    def test_life_upgrade_committed_before_return_and_receipts_preserved(self):
        before,cmd,response=self.legacy()
        store=Store(self.path);world=store.snapshot()
        self.assertEqual(world['revision'],before['revision']+1)
        for old,new in zip(before['citizens'],world['citizens']):
            for key in ('position','goal','intervention','motion_seq','needs','exceptional'):
                self.assertEqual(old.get(key),new.get(key),key)
        disk=json.loads(store.db.execute('SELECT state_json FROM world').fetchone()[0]);self.assertEqual(disk,world)
        self.assertEqual(Service(store,'a'*64,os.getpid()).command(cmd),response)
        self.assertEqual(store.snapshot(),world);store.close()
        store=Store(self.path);self.assertEqual(store.snapshot(),world)
        self.assertEqual(store.db.execute("SELECT count(*) FROM events WHERE kind='city_life_migrated'").fetchone()[0],1)
        validate_world(store.world);store.close()
    def test_life_migration_rolls_back_world_and_event_together(self):
        before,_,_=self.legacy()
        with sqlite3.connect(self.path) as db:
            db.execute("CREATE TRIGGER fail_life BEFORE INSERT ON events WHEN NEW.kind='city_life_migrated' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(sqlite3.IntegrityError):Store(self.path)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(json.loads(db.execute('SELECT state_json FROM world').fetchone()[0]),before)
            db.execute('DROP TRIGGER fail_life')
        store=Store(self.path);self.assertEqual(store.world['life_version'],1);store.close()
    def test_expansion_preserves_all_existing_resident_state_and_receipt(self):
        _,cmd,response=self.legacy();store=Store(self.path);before=store.snapshot();store.close()
        store=Store(self.path,tier=1)
        self.assertEqual(store.world['citizens'][:34],before['citizens'])
        self.assertEqual(store.world['assistance_requests'],before['assistance_requests'])
        self.assertEqual(store.world['agent_history'],before['agent_history'])
        self.assertEqual(len(store.world['citizens']),50)
        self.assertEqual(Service(store,'a'*64,os.getpid()).command(cmd),response)
        after=store.snapshot();store.close()
        store=Store(self.path,tier=1);self.assertEqual(after,store.snapshot());validate_world(store.world);store.close()
    def test_expansion_failure_is_atomic(self):
        store=Store(self.path);before=store.snapshot();store.close()
        with sqlite3.connect(self.path) as db:
            db.execute("CREATE TRIGGER fail_tier BEFORE INSERT ON events WHEN NEW.kind='population_tier_expanded' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(sqlite3.IntegrityError):Store(self.path,tier=1)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(json.loads(db.execute('SELECT state_json FROM world').fetchone()[0]),before)
    def test_expansion_preserves_an_active_assistance_claim(self):
        store=Store(self.path);w=store.world;w['paused']=True
        target=w['citizens'][0];actor=w['citizens'][30]
        target.update(position=[18,.12,-14],navigation='TRAVELLING',activity='travelling')
        target['needs']['social']=98
        actor.update(position=[18,.12,-8],navigation='TRAVELLING',activity='travelling')
        behavior.observe(w,actor);choices=behavior.choose(w,actor)
        chosen=next(item for item in choices if item['subject_id']==target['id'])
        behavior.start_assist(w,actor,chosen,choices,'Upgrade active claim fixture')
        store.commit('active_claim',{});before=store.snapshot();store.close()
        store=Store(self.path,tier=1)
        self.assertEqual(store.world['citizens'][:34],before['citizens'])
        self.assertEqual(store.world['assistance_requests'],before['assistance_requests'])
        validate_world(store.world);store.close()
    def test_unsupported_tier_rejected(self):
        for tier in (3,-1,True):
            with self.assertRaises(ValueError):Store(self.path,tier=tier)
