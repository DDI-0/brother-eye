"""Arbiter locality, fair selection, physical effects and atomic recovery."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch
from backend import agent_behavior as brain
from backend.service import Service, envelope
from backend.store import Store, validate_world

class ArbiterTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'world.sqlite3'
        self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
        w=self.store.world
        for i,c in enumerate(w['citizens']):c['position']=[-60,.12,90]
        a=w['citizens'][30];a.update(position=[18,.12,-8],activity='travelling',navigation='TRAVELLING')
        for index,severity in ((0,95),(1,85)):
            c=w['citizens'][index];p=[18+index*2,.12,-14]
            c['known_places']['park']['position']=p
            c['goal'].update(place='park',position=p,reason='need')
            c.update(position=p,activity='socializing',navigation='ARRIVED')
            c['needs'].update(social=severity,hunger=20,energy=80)
        w['citizens'][2]['needs']['social']=99
        self.store.commit('fixture',{})
    def tearDown(self):self.store.close();self.temp.cleanup()
    @property
    def w(self):return self.store.world
    @property
    def a(self):return self.w['citizens'][30]
    @property
    def subject(self):return self.w['citizens'][0]
    def advance(self,seconds=1):self.service.advance(seconds);validate_world(self.w)
    def report(self,c,position=None,navigation='ARRIVED'):
        return envelope('set_citizen_progress',{'citizen_id':c['id'],'goal_id':c['goal']['id'],'seq':c['motion_seq']+1,'position':position or c['goal']['position'],'yaw':0,'navigation':navigation},str(uuid.uuid4()))
    def arrive(self):self.service.command(self.report(self.a));self.service.command(self.report(self.subject))
    def test_local_severity_ignores_friendship_and_global_oracle(self):
        self.a['exceptional']['relationships'][self.w['citizens'][1]['id']]={'trust':100,'companion':False}
        self.advance()
        e=self.a['exceptional'];self.assertEqual(e['action']['subject_id'],self.subject['id'])
        self.assertNotIn(self.w['citizens'][2]['id'],[o['subject_id'] for o in e['observations']])
        self.assertEqual([c['severity'] for c in e['decision']['candidates']],[94.97,84.97])
        self.assertEqual(len(e['decision']['candidates']),2)
        self.assertTrue(all(c['exceptional']['behavior_stage'] in {'attendant','martyr','sovereign'} for c in self.w['citizens'][31:]))
    def test_ties_age_id_and_claim_exclusion(self):
        self.advance();brain.finish(self.w,self.a,'blocked','fixture')
        self.a['exceptional']['cooldowns'].clear()
        for r in self.w['assistance_requests']:r.update(outcome='open',claimant=None,closed_at=None,severity=90)
        for o in self.a['exceptional']['observations']:o['social']=90
        observed={o['request_id'] for o in self.a['exceptional']['observations']}
        requests=[r for r in self.w['assistance_requests'] if r['id'] in observed];requests[0]['created_at']=0;requests[1]['created_at']=.5
        self.assertEqual(brain.choose(self.w,self.a)[0]['request_id'],requests[0]['id'])
        requests[1]['created_at']=0
        self.assertEqual(brain.choose(self.w,self.a)[0]['request_id'],min(r['id'] for r in requests))
        requests[0].update(outcome='claimed',claimant=self.w['citizens'][31]['id'])
        self.assertEqual(len(brain.choose(self.w,self.a)),1)
        self.w['clock_seconds']=602
        self.assertEqual(brain.choose(self.w,self.a),[])
    def test_physical_dwell_once_learning_restore_and_replay(self):
        core=self.a['exceptional']['core'];self.advance();self.assertEqual(self.subject['needs']['social'],94.97)
        self.advance();self.assertEqual(self.a['exceptional']['action']['elapsed'],0)
        self.arrive();command=self.report(self.subject);response=self.service.command(command)
        for _ in range(5):
            self.service.command(self.report(self.a));self.service.command(self.report(self.subject));self.advance()
        completed=[e for e in self.w['agent_history'] if e['outcome']=='completed']
        self.assertEqual(len(completed),1);self.assertEqual(completed[0]['before_social']-completed[0]['after_social'],5)
        self.assertEqual(self.a['exceptional']['relationships'][self.subject['id']]['trust'],1)
        saved=self.store.snapshot();self.assertEqual(self.service.command(command),response);self.assertEqual(self.store.snapshot(),saved)
        self.store.close();self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
        self.assertEqual(self.store.snapshot(),saved);self.assertEqual(self.a['exceptional']['core'],core)
        self.advance();self.assertEqual(sum(e['outcome']=='completed' for e in self.w['agent_history']),1)
    def test_pause_and_stale_physical_reports_do_not_grant_dwell(self):
        self.advance();self.arrive();self.w['paused']=True;self.advance(20)
        self.assertEqual(self.a['exceptional']['action']['elapsed'],0)
        self.w['paused']=False;self.advance(3)
        self.assertEqual(self.a['exceptional']['action']['elapsed'],0)
    def test_decline_departure_and_block_no_reward(self):
        for outcome in ('declined','departed','blocked'):
            with self.subTest(outcome=outcome):
                original=self.store.snapshot();self.advance();self.arrive()
                before=self.subject['needs']['social']
                if outcome=='declined':self.subject['activity']='travelling'
                if outcome=='departed':self.subject['position'][0]+=5
                if outcome=='blocked':self.a['navigation']='WAITING FOR ROUTE'
                brain.advance(self.w,1)
                self.assertEqual(self.w['agent_history'][-1]['outcome'],outcome)
                self.assertEqual(self.subject['needs']['social'],before)
                self.assertEqual(self.a['exceptional']['relationships'].get(self.subject['id'],{}).get('trust',0),-1 if outcome=='declined' else 0)
                self.assertGreater(self.a['exceptional']['cooldowns'][self.subject['id']],self.w['clock_seconds'])
                self.store.world=original
    def test_urgent_recovery_and_held_override_interrupt_claim(self):
        self.advance();self.a['needs']['energy']=5;self.advance()
        self.assertEqual(self.a['goal']['place'],'home');self.assertEqual(self.a['goal']['reason'],'need')
        self.assertIsNone(self.a['exceptional']['action'])
        self.a['needs']['energy']=82;self.advance()
        c=self.a;core=c['exceptional']['core']
        command=envelope('intervene',{'world_id':self.w['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,'action':'assign_destination','place':'food','reason':'Interrupt local assistance'},str(uuid.uuid4()))
        self.service.command(command);held=self.a['goal']['id'];self.advance(10)
        self.assertEqual(self.a['goal']['id'],held);self.assertIsNone(self.a['exceptional']['action']);self.assertEqual(self.a['exceptional']['core'],core)
        command=envelope('intervene',{**command['payload'],'expected_goal_id':held,'expected_intervention_id':command['id'],'action':'release','place':None},str(uuid.uuid4()))
        self.service.command(command);self.advance();self.assertEqual(self.a['goal']['reason'],'ideology');self.assertNotEqual(self.a['goal']['id'],held)
    def test_failure_rolls_back_effect_trust_memory_audit_and_clock(self):
        self.advance();self.arrive();self.a['exceptional']['action']['elapsed']=4
        before=self.store.snapshot();sql=self.store.db.execute('SELECT state_json FROM world').fetchone()[0]
        self.store.db.execute("CREATE TRIGGER fail_agent BEFORE INSERT ON events WHEN NEW.kind='agent_activity' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(Exception):self.service.advance(1)
        self.assertEqual(self.store.snapshot(),before);self.assertEqual(self.store.db.execute('SELECT state_json FROM world').fetchone()[0],sql)
    def test_schema_five_migration_keeps_records_override_and_receipts(self):
        self.w.update(paused=True,clock_seconds=125)
        c=self.subject
        command=envelope('intervene',{'world_id':self.w['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,'action':'assign_destination','place':'home','reason':'Preserve held legacy override'},str(uuid.uuid4()))
        response=self.service.command(command)
        receipt=self.store.db.execute('SELECT request_json,response_json FROM receipts').fetchall()
        for c in self.w['citizens'][30:]:
            e=c['exceptional'];e['behavior_stage']='foundation'
            for k in ('action','decision','cooldowns','next_observation_at'):del e[k]
        del self.w['assistance_requests'];del self.w['agent_history']
        self.store.commit('legacy_fixture',{});old=self.store.snapshot()
        self.store.db.execute('PRAGMA user_version=5');self.store.db.commit();self.store.close();self.store=Store(self.path)
        self.service=Service(self.store,'a'*64,os.getpid());validate_world(self.w)
        self.assertEqual(self.service.command(command),response)
        self.assertLess(response['payload']['state']['revision'],self.w['revision'])
        self.assertEqual(receipt,self.store.db.execute('SELECT request_json,response_json FROM receipts').fetchall())
        self.assertEqual(self.w['citizens'][:30],old['citizens'][:30]);self.assertEqual(self.w['revision'],old['revision']+1)
        for before,after in zip(old['citizens'][30:],self.w['citizens'][30:]):
            self.assertEqual({k:v for k,v in before.items() if k!='exceptional'},{k:v for k,v in after.items() if k!='exceptional'})
        saved=self.store.snapshot();self.store.close();self.store=Store(self.path);self.assertEqual(saved,self.store.snapshot())
    def test_bounds_and_immutable_core(self):
        self.advance()
        for mutation in (lambda w:w['citizens'][30]['exceptional'].update(core='changed'),lambda w:w['citizens'][30]['exceptional']['observations'].append({}),lambda w:w['citizens'][31]['exceptional'].update(behavior_stage='arbiter'),lambda w:w['citizens'][30]['exceptional']['cooldowns'].update({str(uuid.uuid4()):5})):
            w=copy.deepcopy(self.w);mutation(w)
            with self.assertRaises(ValueError):validate_world(w)

    def test_claim_and_interruption_rollback_and_replay(self):
        # A failed movement transaction must not leave a claim or observed memory behind.
        before=self.store.snapshot()
        self.store.db.execute("CREATE TRIGGER fail_move BEFORE INSERT ON events WHEN NEW.kind='set_citizen_progress' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(Exception):self.service.command(self.report(self.subject))
        self.assertEqual(self.store.snapshot(),before)
        self.store.db.execute('DROP TRIGGER fail_move')
        self.advance();self.arrive();c=self.a
        command=envelope('intervene',{'world_id':self.w['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,'action':'assign_destination','place':'home','reason':'Pause this local mission'},str(uuid.uuid4()))
        before=self.store.snapshot()
        self.store.db.execute("CREATE TRIGGER fail_redirect BEFORE INSERT ON events WHEN NEW.kind='intervene' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(Exception):self.service.command(command)
        self.assertEqual(self.store.snapshot(),before)
        self.store.db.execute('DROP TRIGGER fail_redirect')
        response=self.service.command(command);saved=self.store.snapshot()
        self.assertEqual(self.service.command(command),response);self.assertEqual(saved,self.store.snapshot())
        self.assertEqual(sum(e['outcome']=='interrupted' for e in self.w['agent_history']),1)
        self.assertIsNone(self.a['exceptional']['action'])

    def test_contact_capacity_turnover_keeps_learning_and_companions(self):
        c=self.w['citizens'][33];relations=c['exceptional']['relationships']
        companion=self.w['citizens'][1]['id']
        for person in self.w['citizens'][2:9]:relations[person['id']]={'trust':10,'companion':False}
        self.assertEqual(len(relations),8)
        brain.trust(c,self.subject['id'],1)
        self.assertEqual(len(relations),8);self.assertEqual(relations[self.subject['id']]['trust'],1)
        self.assertEqual(relations[companion],{'trust':25,'companion':True})
        # Test the shared primitive; the Sovereign's autonomous producer remains disabled.
