"""5D contrasting decisions, voluntary local coordination and migration/atomicity."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
import uuid
from backend import agent_behavior as b, agent_policies as p
from backend.service import Service, envelope
from backend.store import Store, validate_world

class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'world.sqlite3'
        self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
        for c in self.w['citizens']:c['position']=[-60,.12,90]
        self.w.update(clock_seconds=10.,paused=False)
        for index,social in ((0,98),(1,85)):
            c=self.w['citizens'][index];c['position']=[18+index*2,.12,-14];c['needs'].update(social=social,hunger=20,energy=80)
            c['known_places']['park']['position']=c['position'].copy();c['goal'].update(place='park',position=c['position'].copy(),reason='need')
            c.update(activity='socializing',navigation='ARRIVED',physical_at=10.)
    def tearDown(self):self.store.close();self.temp.cleanup()
    @property
    def w(self):return self.store.world
    def actor(self,index):
        c=self.w['citizens'][index];c['position']=[18,.12,-8]
        return c
    def stationary(self,c,point):
        c['position']=point.copy();c['known_places']['park']['position']=point.copy()
        c['goal'].update(place='park',position=point.copy(),reason='ideology');c.update(activity='socializing',navigation='ARRIVED',physical_at=self.w['clock_seconds'])
        c['exceptional']['action']={'kind':'observe','request_id':None,'subject_id':None,'goal_id':c['goal']['id'],'elapsed':0.,'selected_at':self.w['clock_seconds'],'observed_position':None,'evidence_id':None}
    def arrive(self,c):c.update(position=c['goal']['position'].copy(),activity='conferring' if c['goal']['place']=='contact' else 'assisting',navigation='ARRIVED',physical_at=self.w['clock_seconds'])
    def dwell(self,c,subject):
        for _ in range(5):
            if c['exceptional']['action'] is None:break
            self.w['clock_seconds']+=1;c['physical_at']=self.w['clock_seconds'];subject['physical_at']=self.w['clock_seconds']
            if c['exceptional']['action']['kind']=='assist':b.advance(self.w,1)
            else:p.advance_contact(self.w,c,1)
    def test_same_opportunities_distinct_core_choices(self):
        original=self.store.snapshot();choices=[]
        for index in range(30,34):
            self.store.world=copy.deepcopy(original);c=self.actor(index);b.observe(self.w,c)
            self.assertTrue(p.select(self.w,c,b.choose(self.w,c)))
            action=c['exceptional']['action'];choices.append(action['kind'])
            if index==30:self.assertEqual(action['subject_id'],self.w['citizens'][0]['id'])
            if index==31:self.assertEqual(action['kind'],'inspect')
            if index==32:self.assertIsNotNone(c['exceptional']['project'])
            if index==33:self.assertEqual(action['subject_id'],self.w['citizens'][1]['id'])
            validate_world(self.w)
        self.assertEqual(choices,['assist','inspect','assist','assist'])
    def test_four_agent_contention_override_replay_and_restore(self):
        for index in range(30,34):self.actor(index)
        cores=[copy.deepcopy(c['exceptional']['core']) for c in self.w['citizens'][30:]]
        b.advance(self.w,.05)
        agents=self.w['citizens'][30:]
        self.assertEqual([c['exceptional']['action']['kind'] for c in agents],['assist','inspect','coordinate','assist'])
        claims=[r for r in self.w['assistance_requests'] if r['outcome']=='claimed']
        self.assertEqual(len(claims),2)
        self.assertEqual(len({r['subject_id'] for r in claims}),2)
        target=agents[0];old_request=target['exceptional']['action']['request_id']
        command=envelope('intervene',{'world_id':self.w['world_id'],'citizen_id':target['id'],'expected_goal_id':target['goal']['id'],'expected_intervention_id':None,'action':'assign_destination','place':'home','reason':'Combined conflict acceptance'},str(uuid.uuid4()))
        response=self.service.command(command)
        self.assertEqual(b.request_for(self.w,old_request)['outcome'],'interrupted')
        held=self.w['citizens'][30]['goal']['id']
        self.service.advance(.05)
        self.assertEqual(self.w['citizens'][30]['goal']['id'],held)
        validate_world(self.w)
        self.w['paused']=True;self.store.commit('combined_checkpoint',{})
        saved=self.store.snapshot();self.store.close();self.store=Store(self.path)
        self.service=Service(self.store,'a'*64,os.getpid())
        self.assertEqual(saved,self.store.snapshot())
        self.assertEqual(self.service.command(command),response)
        self.assertEqual(saved,self.store.snapshot())
        self.assertEqual(cores,[c['exceptional']['core'] for c in self.w['citizens'][30:]])
        self.assertFalse(any(e['outcome']=='completed' for e in self.w['agent_history']))
    def test_competing_offers_cannot_steal_claim_or_share_expired_evidence(self):
        c,helper=self.prepare_offer();offer=copy.deepcopy(b.choose(self.w,c)[0])
        rival=self.actor(33)
        b.start_assist(self.w,rival,offer,[offer],'Competing claim fixture')
        self.dwell(c,helper)
        self.assertEqual(self.w['agent_history'][-1]['outcome'],'expired')
        self.assertEqual(b.request_for(self.w,offer['request_id'])['claimant'],rival['id'])
        self.assertEqual(helper['exceptional']['observations'],[])
        self.assertNotIn(helper['id'],c['exceptional']['relationships'])
        validate_world(self.w)
    def test_resolved_unclaimed_project_tasks_close_without_reward(self):
        c,partner=self.prepare_offer()
        project=c['exceptional']['project']
        for target in self.w['citizens'][:2]:target['needs']['social']=50
        before=[target['needs'].copy() for target in self.w['citizens'][:2]]
        self.w['clock_seconds']+=5
        c.update(position=[18,.12,-8],navigation='TRAVELLING',activity='travelling')
        b.observe(self.w,c);p.project_refresh(self.w,c)
        self.assertEqual(project['status'],'completed')
        self.assertEqual(set(project['outcomes'].values()),{'expired'})
        self.assertEqual(before,[target['needs'] for target in self.w['citizens'][:2]])
        self.assertFalse(any(event['outcome']=='completed' for event in self.w['agent_history']))
        validate_world(self.w)
    def test_project_evidence_expiry_releases_project_but_preserves_claim(self):
        c,partner=self.prepare_offer();self.dwell(c,partner)
        project=c['exceptional']['project'];claimed=project['delegated_request_id']
        self.w['clock_seconds']+=601
        p.project_refresh(self.w,c)
        self.assertEqual(b.request_for(self.w,claimed)['outcome'],'claimed')
        self.assertEqual(project['status'],'delegated')
        self.assertEqual(set(project['outcomes'].values()),{'expired'})
        b.finish(self.w,partner,'expired','fixture expired active claim')
        p.project_refresh(self.w,c)
        self.assertEqual(project['status'],'completed')
        self.assertEqual(len(project['outcomes']),len(project['request_ids']))
        validate_world(self.w)
    def test_attendant_uncertainty_reliability_and_verified_fact_no_reward(self):
        c=self.actor(31);friend=self.w['citizens'][1];c['exceptional']['relationships'][friend['id']]={'trust':10,'companion':False}
        b.observe(self.w,c);items=p.information_candidates(self.w,c);self.assertEqual(items[0]['subject_id'],friend['id'])
        p.select(self.w,c,b.choose(self.w,c));self.arrive(c);before=friend['needs'].copy();self.dwell(c,friend)
        self.assertEqual(friend['needs'],before);self.assertEqual(c['exceptional']['relationships'][friend['id']]['trust'],11)
        self.assertEqual(c['exceptional']['information'][friend['id']]['social'],85)
        self.assertNotIn(friend['id'],[i['subject_id'] for i in p.information_candidates(self.w,c)])
        self.assertEqual(self.w['agent_history'][-1]['outcome'],'verified');validate_world(self.w)
    def test_contact_failures_do_not_invent_information_or_cooperation(self):
        for outcome in ('declined','departed','blocked'):
            with self.subTest(outcome=outcome):
                old=self.store.snapshot();c=self.actor(31);b.observe(self.w,c);p.select(self.w,c,b.choose(self.w,c));subject=next(x for x in self.w['citizens'] if x['id']==c['exceptional']['action']['subject_id']);self.arrive(c)
                if outcome=='declined':subject['activity']='travelling'
                elif outcome=='departed':subject['position'][0]+=8
                else:c['navigation']='WAITING FOR ROUTE'
                p.advance_contact(self.w,c,1);self.assertEqual(self.w['agent_history'][-1]['outcome'],outcome)
                self.assertEqual(c['exceptional']['information'],{});self.assertIsNone(c['exceptional']['action'])
                self.assertEqual(c['exceptional']['relationships'].get(subject['id'],{}).get('trust',0),-1 if outcome=='declined' else 0)
                self.store.world=old
    def prepare_offer(self,accept=True):
        martyr=self.actor(32);partner=self.w['citizens'][30]
        self.stationary(partner,[16,.12,-8]);b.observe(self.w,martyr)
        # Partner has not sensed the recipients yet; information is delivered by the offer.
        partner['exceptional']['next_observation_at']=self.w['clock_seconds']+5
        if not accept:partner['needs']['energy']=5
        self.assertTrue(p.select(self.w,martyr,b.choose(self.w,martyr)))
        self.assertEqual(martyr['exceptional']['action']['kind'],'coordinate')
        self.arrive(martyr);return martyr,partner
    def test_martyr_offer_accepts_once_and_shares_only_local_evidence(self):
        c,partner=self.prepare_offer();recipient=self.w['citizens'][0];before=recipient['needs'].copy();self.dwell(c,partner)
        self.assertEqual(c['exceptional']['project']['status'],'delegated')
        action=partner['exceptional']['action'];self.assertEqual(action['kind'],'assist');self.assertEqual(action['subject_id'],recipient['id'])
        self.assertEqual(recipient['needs'],before);self.assertEqual(recipient['goal']['place'],'park')
        shared=partner['exceptional']['observations'];self.assertEqual(len(shared),1);self.assertEqual(shared[0]['source'],'coordination:'+c['id']);self.assertEqual(shared[0]['at'],10)
        self.assertEqual(b.request_for(self.w,action['request_id'])['claimant'],partner['id'])
        self.assertEqual(c['exceptional']['relationships'][partner['id']]['trust'],1)
        validate_world(self.w)
        self.arrive(partner)
        for _ in range(5):
            self.w['clock_seconds']+=1;partner['physical_at']=self.w['clock_seconds'];recipient['physical_at']=self.w['clock_seconds']
            # Keep the project owner from separately starting its next task in this slice.
            self.w['paused']=False
            b.advance(self.w,1)
        self.assertEqual(sum(e['outcome']=='completed' for e in self.w['agent_history']),1)
        p.project_refresh(self.w,c)
        self.assertIn('completed',c['exceptional']['project']['outcomes'].values());validate_world(self.w)
    def test_refusal_changes_partner_tactics_then_solo_fallback(self):
        c,partner=self.prepare_offer(False);self.dwell(c,partner)
        self.assertEqual(self.w['agent_history'][-1]['outcome'],'declined')
        self.assertEqual(c['exceptional']['relationships'][partner['id']]['trust'],-1)
        self.assertTrue(p.select(self.w,c,b.choose(self.w,c)));self.assertEqual(c['exceptional']['action']['kind'],'assist')
        self.assertEqual(c['exceptional']['project']['status'],'active');validate_world(self.w)
    def test_sovereign_own_urgent_then_companion_and_refuses_stranger_offer(self):
        c=self.actor(33);b.observe(self.w,c);requests=b.choose(self.w,c)
        stranger=next(i for i in requests if i['subject_id']==self.w['citizens'][0]['id'])
        self.assertFalse(p.willing(self.w,c,stranger));c['needs']['energy']=5;b.advance(self.w,1)
        self.assertEqual(c['goal']['place'],'home');self.assertEqual(c['goal']['reason'],'need')
        c['needs']['energy']=82;b.advance(self.w,1)
        self.assertEqual(c['exceptional']['action']['subject_id'],self.w['citizens'][1]['id'])
        validate_world(self.w)
    def test_partner_commitment_and_arbiter_fairness_block_offer(self):
        c=self.actor(30);b.observe(self.w,c);requests=b.choose(self.w,c)
        self.assertFalse(p.willing(self.w,c,requests[1]));self.assertTrue(p.willing(self.w,c,requests[0]))
        p.select(self.w,c,requests);self.assertFalse(p.willing(self.w,c,requests[0]))
        ordinary=self.w['citizens'][0];self.assertFalse(p.willing(self.w,ordinary,requests[0]))
    def test_attendant_current_information_uses_trusted_known_partner(self):
        c=self.actor(31);partner=self.w['citizens'][30];self.stationary(partner,[16,.12,-8]);b.observe(self.w,c)
        for obs in c['exceptional']['observations']:c['exceptional']['information'][obs['subject_id']]={'at':10,'social':obs['social'],'source_id':obs['subject_id']}
        c['exceptional']['relationships'][partner['id']]={'trust':12,'companion':False}
        p.select(self.w,c,b.choose(self.w,c));self.assertEqual(c['exceptional']['action']['kind'],'coordinate')
        self.assertEqual(c['exceptional']['action']['subject_id'],partner['id']);validate_world(self.w)
    def test_schema_six_keeps_partial_arbiter_claim_and_old_receipt(self):
        a=self.actor(30);b.observe(self.w,a);p.select(self.w,a,b.choose(self.w,a));a['exceptional']['action']['elapsed']=2
        self.w['paused']=True
        request=envelope('set_clock',{'paused':True,'time_scale':1},str(uuid.uuid4()));response=self.service.command(request)
        for c in self.w['citizens'][30:]:
            del c['exceptional']['information']
            if c is not a:c['exceptional']['behavior_stage']='foundation'
        self.store.commit('legacy_fixture',{});old=self.store.snapshot();receipts=self.store.db.execute('SELECT * FROM receipts').fetchall()
        self.store.db.execute('PRAGMA user_version=6');self.store.db.commit();self.store.close();self.store=Store(self.path);self.service=Service(self.store,'a'*64,os.getpid())
        self.assertEqual(self.w['citizens'][:30],old['citizens'][:30]);self.assertEqual(self.w['citizens'][30]['exceptional']['action'],old['citizens'][30]['exceptional']['action'])
        self.assertEqual(self.w['assistance_requests'],old['assistance_requests']);self.assertEqual(self.w['agent_history'],old['agent_history'])
        self.assertEqual(self.w['revision'],old['revision']+1);self.assertEqual(receipts,self.store.db.execute('SELECT * FROM receipts').fetchall());self.assertEqual(self.service.command(request),response)
        saved=self.store.snapshot();self.store.close();self.store=Store(self.path);self.assertEqual(saved,self.store.snapshot());validate_world(self.w)
    def test_coordination_atomic_failure_and_pause_no_effect(self):
        c,partner=self.prepare_offer();c['exceptional']['action']['elapsed']=4
        self.w['paused']=True;before=self.store.snapshot();b.advance(self.w,10);self.assertEqual(before,self.store.snapshot())
        self.w['paused']=False;before=self.store.snapshot()
        self.store.db.execute("CREATE TRIGGER fail_agent BEFORE INSERT ON events WHEN NEW.kind='agent_activity' BEGIN SELECT RAISE(ABORT,'injected'); END")
        with self.assertRaises(Exception):self.service.advance(1)
        self.assertEqual(before,self.store.snapshot())
    def test_project_override_retains_evidence_and_release_replans(self):
        c,partner=self.prepare_offer();project=copy.deepcopy(c['exceptional']['project']);core=c['exceptional']['core']
        command=envelope('intervene',{'world_id':self.w['world_id'],'citizen_id':c['id'],'expected_goal_id':c['goal']['id'],'expected_intervention_id':None,'action':'assign_destination','place':'home','reason':'Temporarily redirect organiser'},str(uuid.uuid4()))
        self.service.command(command);c=self.w['citizens'][32]
        self.assertEqual(c['exceptional']['project'],project);self.assertIsNone(c['exceptional']['action'])
        held=c['goal']['id'];self.service.advance(1);self.assertEqual(self.w['citizens'][32]['goal']['id'],held)
        c=self.w['citizens'][32];release=envelope('intervene',{**command['payload'],'expected_goal_id':held,'expected_intervention_id':command['id'],'action':'release','place':None},str(uuid.uuid4()))
        self.service.command(release);self.service.advance(1);c=self.w['citizens'][32]
        self.assertEqual(c['exceptional']['core'],core);self.assertEqual(c['exceptional']['project']['id'],project['id']);self.assertNotEqual(c['goal']['id'],held)

    def test_offers_cannot_bypass_self_target_pair_cooldown_or_existing_claim(self):
        c=self.actor(30);b.observe(self.w,c);offer=b.choose(self.w,c)[0]
        self.assertFalse(p.willing(self.w,c,{**offer,'subject_id':c['id']}))
        b.cooldown(self.w,c,offer['subject_id']);self.assertFalse(p.willing(self.w,c,offer))
        c['exceptional']['cooldowns'].clear();b.start_assist(self.w,c,offer,[offer],'Acceptance fixture')
        other=self.actor(33)
        with self.assertRaises(ValueError):b.start_assist(self.w,other,offer,[offer],'Cannot claim twice')
        self.assertEqual(b.request_for(self.w,offer['request_id'])['claimant'],c['id']);validate_world(self.w)

    def test_learned_decline_reorders_partner_preference(self):
        c=self.actor(32);first=self.w['citizens'][30];second=self.w['citizens'][31]
        self.stationary(first,[16,.12,-8]);self.stationary(second,[20,.12,-8]);b.observe(self.w,c)
        preferred=p.partners(self.w,c)[0]['subject_id']
        b.trust(c,preferred,-1)
        self.assertNotEqual(p.partners(self.w,c)[0]['subject_id'],preferred)
        self.assertEqual(c['exceptional']['core'],'Personally bears responsibility for remaking society and sees their own plan as the necessary path.')
