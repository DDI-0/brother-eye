import asyncio
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from backend.citizens import plan
from backend.evaluation import evaluate
from backend.service import Service, envelope
from backend.store import Store, new_world


class EvaluationTests(unittest.TestCase):
    def setUp(self):
        self.world=new_world()
        for c in self.world['citizens']:
            c['needs']={'hunger':10.,'energy':80.,'social':20.}
            c['navigation']='ARRIVED';c['activity']='working'
        self.c=self.world['citizens'][0]
    def own(self):return [f for f in evaluate(self.world)['findings'] if f['citizen_id']==self.c['id']]
    def test_threshold_boundaries_and_priorities(self):
        for key,boundary,normal,attention,urgent in [('hunger',70,70,70.01,90),('energy',20,20,19.99,10),('social',75,75,75.01,95)]:
            with self.subTest(key=key):
                original=copy.deepcopy(self.c['needs'])
                self.c['needs'][key]=normal;self.assertEqual(self.own(),[])
                self.c['needs'][key]=attention;f=self.own()[0];self.assertEqual(f['priority'],'attention');self.assertEqual(f['evidence']['threshold'],boundary)
                self.c['needs'][key]=urgent;self.assertEqual(self.own()[0]['priority'],'urgent')
                self.c['needs']=original
    def test_recovery_context_uses_actual_arrival(self):
        self.c['needs']['hunger']=95;plan(self.c,0)
        self.assertEqual(self.own()[0]['response'],'travelling_to_recovery')
        self.c.update(navigation='ARRIVED',activity='eating')
        finding=self.own()[0];self.assertEqual(finding['response'],'recovering');self.assertIn('Allow recovery',finding['recommendation'])
        self.c['navigation']='TRAVELLING';self.assertEqual(self.own()[0]['response'],'not_addressed')
    def test_route_wait_and_crowd_wait_differ(self):
        self.c['navigation']='WAITING FOR ROUTE';self.assertEqual(self.own()[0]['priority'],'attention')
        self.assertIn('does not establish how long',self.own()[0]['explanation'])
        self.c['navigation']='WAITING FOR SPACE';f=self.own()[0]
        self.assertEqual(f['priority'],'notice');self.assertEqual(f['code'],'space_wait')
    def test_idle_is_not_a_fault_and_no_stall_is_invented(self):
        for activity,navigation in [('working','ARRIVED'),('resting','ARRIVED'),('travelling','TRAVELLING')]:
            self.c.update(activity=activity,navigation=navigation)
            self.assertEqual(self.own(),[])
    def test_pure_stable_detached_and_snapshot_bound(self):
        self.c['needs'].update(hunger=99,energy=1,social=99)
        before=copy.deepcopy(self.world);report=evaluate(self.world)
        self.assertEqual(report,evaluate(self.world));self.assertEqual(before,self.world)
        self.assertEqual(report['source']['world_id'],self.world['world_id'])
        self.assertEqual(report['summary']['residents_flagged'],1)
        self.assertEqual(report['summary']['priorities']['urgent'],3)
        self.assertEqual(len({f['id'] for f in report['findings']}),3)
        report['findings'][0]['evidence']['value']=0;self.assertEqual(before,self.world)
    def test_empty_is_unknown_not_all_clear(self):
        report=evaluate({});self.assertEqual(report['coverage'],'unavailable_or_incomplete')
        self.assertEqual(report['summary']['mean_needs'],{})
        incomplete=copy.deepcopy(self.world);incomplete['citizens'][0].pop('needs')
        self.assertEqual(evaluate(incomplete)['coverage'],'unavailable_or_incomplete')
    def test_wire_projection_is_derived_not_persisted(self):
        class Peer:
            async def send(self,raw):self.message=json.loads(raw)
        with tempfile.TemporaryDirectory() as name:
            store=Store(Path(name)/'world.sqlite3');service=Service(store,'a'*64,os.getpid());peer=Peer()
            before=store.snapshot();message=envelope('snapshot',{'state':before})
            asyncio.run(service.send(peer,message))
            self.assertEqual(peer.message['payload']['assessment'],evaluate(before))
            self.assertNotIn('assessment',message['payload']);self.assertEqual(store.snapshot(),before)
            self.assertNotIn('assessment',json.loads(store.db.execute('SELECT state_json FROM world').fetchone()[0]))
            store.close()
