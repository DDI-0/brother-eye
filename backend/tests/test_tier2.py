"""100-person expansion preserves old world work and bounds new venue capacity."""
import copy
import json
import math
from pathlib import Path
import sqlite3
import tempfile
import unittest
from backend.store import Store, new_world, validate_world
from backend.service import Service, envelope
from backend.retention import command_id
from backend import agent_behavior as behavior

class Tier2Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'world.sqlite3'
    def tearDown(self):self.temp.cleanup()
    def test_fresh_demographics_capacity_and_known_spot_spacing(self):
        for _ in range(3):
            w=new_world(tier=2);validate_world(w);people=w['citizens']
            self.assertEqual(len(people),100)
            self.assertEqual(len({c['name'] for c in people}),100)
            self.assertEqual(sum(c['kind']=='civilian' for c in people),91)
            self.assertEqual(w['population_tier'],2)
            for venue in ('home','food','park','work'):
                positions=[c['known_places'][venue]['position'] for c in people]
                for i,a in enumerate(positions):
                    for b in positions[i+1:]:
                        if abs(a[1]-b[1])<2:self.assertGreaterEqual(math.hypot(a[0]-b[0],a[2]-b[2]),1.35)
    def test_both_upgrades_preserve_world_commands_and_reopen_without_downgrade(self):
        for tier in (0,1):
            path=self.path.with_name(str(tier)+'.sqlite3');s=Store(path,tier=tier)
            s.world['paused']=True;service=Service(s,'a'*64,0);c=s.world['citizens'][0]
            payload={'world_id':s.world['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,'action':'assign_destination','place':'food','reason':'Preserve in-flight authority through expansion'}
            request={**envelope('intervene',payload,command_id(s.world['world_id'],1)),'serial':1}
            ack=service.command(request);before=s.snapshot();s.close()
            s=Store(path,tier=2);after=s.snapshot()
            self.assertEqual(after['citizens'][:len(before['citizens'])],before['citizens'])
            for key in ('clock_seconds','tick','world_id','command_serial','intervention_history','assistance_requests'):
                self.assertEqual(after[key],before[key])
            self.assertEqual(s.receipt(request['id'],request),ack)
            validate_world(after);s.close();s=Store(path,tier=1)
            self.assertEqual(s.snapshot(),after);self.assertEqual(s.db.execute('PRAGMA quick_check').fetchone()[0],'ok');s.close()
    def test_upgrade_failure_rolls_back_both_population_steps(self):
        s=Store(self.path);before=s.snapshot();s.close()
        with sqlite3.connect(self.path) as db:
            db.execute("CREATE TRIGGER fail_tier BEFORE INSERT ON events WHEN NEW.kind='population_tier_expanded' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(sqlite3.IntegrityError):Store(self.path,tier=2)
        with sqlite3.connect(self.path) as db:
            self.assertEqual(json.loads(db.execute('SELECT state_json FROM world').fetchone()[0]),before)
    def test_upgrade_preserves_active_agent_claim_and_core(self):
        s=Store(self.path,tier=1);w=s.world;w['paused']=True
        target=w['citizens'][0];actor=w['citizens'][30]
        target.update(position=[18,.12,-14],navigation='TRAVELLING',activity='travelling');target['needs']['social']=98
        actor.update(position=[18,.12,-8],navigation='TRAVELLING',activity='travelling')
        behavior.observe(w,actor);choices=behavior.choose(w,actor)
        chosen=next(c for c in choices if c['subject_id']==target['id'])
        behavior.start_assist(w,actor,chosen,choices,'100-person migration claim fixture')
        s.commit('claim_fixture',{});before=s.snapshot();s.close();s=Store(self.path,tier=2)
        self.assertEqual(s.world['citizens'][:50],before['citizens'])
        self.assertEqual(s.world['assistance_requests'],before['assistance_requests']);validate_world(s.world);s.close()
