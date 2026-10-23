"""Shared local deterministic Exceptional Agent behavior. All effects use confirmed physical records."""
from copy import deepcopy
import math
import uuid

STAGE = 'arbiter'
TERMINAL = {'completed', 'declined', 'departed', 'blocked', 'interrupted', 'expired'}


def active(c):
    return c.get('exceptional', {}).get('behavior_stage') in {'arbiter','attendant','martyr','sovereign'}


def migrate(world):
    world.setdefault('assistance_requests', [])
    world.setdefault('agent_history', [])
    for c in world['citizens']:
        if c.get('kind') != 'exceptional':
            continue
        e = c['exceptional']
        e.update(action=None, decision=None, cooldowns={}, next_observation_at=world['clock_seconds'])
        if e['profile'] == 'arbiter_of_dawn':
            e['behavior_stage'] = STAGE


def emit(world, c, outcome, detail, request=None, evidence=(), before=None, after=None, subject=None, fact=None):
    from backend.citizens import remember
    event = {'id': str(uuid.uuid4()), 'at': world['clock_seconds'], 'agent_id': c['id'],
             'outcome': outcome, 'detail': detail, 'request_id': request['id'] if request else None,
             'subject_id': request['subject_id'] if request else subject, 'evidence': list(evidence),
             'fact':deepcopy(fact),
             'before_social': before, 'after_social': after,
             'decision': deepcopy(c['exceptional']['decision']) if outcome=='selected' else None}
    world['agent_history'].append(event)
    world['agent_history'] = world['agent_history'][-64:]
    remember(c, world['clock_seconds'], 'decision' if outcome == 'selected' else 'experience', detail)


def nearby(a, b, radius):
    return abs(a['position'][1]-b['position'][1]) <= 2 and math.dist(a['position'], b['position']) <= radius


def request_for(world, identifier):
    return next((r for r in world['assistance_requests'] if r['id'] == identifier), None)


def cooldown(world,c,target):
    e=c['exceptional'];e['cooldowns'][target]=world['clock_seconds']+60
    e['cooldowns']=dict(sorted(e['cooldowns'].items(),key=lambda item:item[1])[-16:])


def finish(world, c, outcome, detail):
    e = c['exceptional']; action = e['action']
    if not action:
        return
    request = request_for(world, action['request_id']) if action['request_id'] else None
    if request and request['claimant'] == c['id'] and request['outcome'] == 'claimed':
        request.update(outcome=outcome, closed_at=world['clock_seconds'])
        e['cooldowns'][request['subject_id']] = world['clock_seconds']+60
        # Capacity is bounded; evict earliest expiry rather than increasing storage.
        e['cooldowns'] = dict(sorted(e['cooldowns'].items(), key=lambda item: item[1])[-16:])
        if outcome == 'declined':
            trust(c, request['subject_id'], -1)
        emit(world, c, outcome, detail, request)
    if action['kind'] in {'inspect','coordinate'}:
        cooldown(world,c,action['subject_id'])
        if outcome=='declined':trust(c,action['subject_id'],-1)
        emit(world,c,outcome,detail,evidence=[action['evidence_id']],subject=action['subject_id'])
    e['action'] = None


def interrupt(world, c):
    if active(c):
        finish(world, c, 'interrupted', 'Neon Providence redirected travel; ideology remains unchanged.')


def trust(c, subject, change):
    relations = c['exceptional']['relationships']
    if subject not in relations:
        if len(relations) >= 8:
            # Fixed companions survive bounded contact turnover; stable IDs break ties.
            removable=sorted(target for target,value in relations.items() if not value['companion'])
            if removable:del relations[removable[0]]
        if len(relations) < 8:relations[subject] = {'trust': 0, 'companion': False}
    if subject in relations:
        relations[subject]['trust'] = max(-100, min(100, relations[subject]['trust']+change))


def observe(world, c):
    e = c['exceptional']; now = world['clock_seconds']
    if now < e['next_observation_at']:
        return
    e['next_observation_at'] = now+5
    observations = {o['subject_id']: o for o in e['observations'] if now-o['at'] <= 600}
    for subject in world['citizens']:
        if subject['id'] == c['id'] or not nearby(c, subject, 8):
            continue
        severity = subject['needs']['social']
        request = next((r for r in world['assistance_requests'] if r['subject_id'] == subject['id'] and r['outcome'] in {'open', 'claimed'}), None)
        if request and request['outcome']=='open' and severity<=75:
            request.update(outcome='expired',closed_at=now)
            emit(world,c,'expired','Locally observed that the unclaimed social need has resolved.',request)
            request=None
        if severity > 75 and not request and e['cooldowns'].get(subject['id'], 0) <= now:
            # Preserve every active claim; retire oldest terminal records first.
            if len(world['assistance_requests']) >= 64:
                protected={identifier for person in world['citizens'] for identifier in ((person.get('exceptional',{}).get('project') or {}).get('request_ids',[])) if identifier not in (person.get('exceptional',{}).get('project') or {}).get('outcomes',{})}
                retired = next((r for r in world['assistance_requests'] if r['outcome'] in TERMINAL and r['id'] not in protected), None)
                if retired:world['assistance_requests'].remove(retired)
            if len(world['assistance_requests']) < 64:
                request = {'id': str(uuid.uuid4()), 'subject_id': subject['id'], 'created_at': now,
                           'severity': severity, 'claimant': None, 'outcome': 'open', 'closed_at': None}
                world['assistance_requests'].append(request)
                emit(world, c, 'observed', 'Locally observed an unmet social assistance request from '+subject['name'], request)
        if request and request['outcome'] == 'open':request['severity'] = severity
        observations[subject['id']] = {'id': str(uuid.uuid4()), 'subject_id': subject['id'], 'at': now,
            'source': 'local_proximity', 'social': severity, 'position': list(subject['position']),
            'request_id': request['id'] if request else None}
    # Keep newest, then stable identity, without global evidence leaking into planning.
    e['observations'] = sorted(observations.values(), key=lambda o: (-o['at'], o['subject_id']))[:16]


def choose(world, c):
    e = c['exceptional']; now = world['clock_seconds']; candidates = []
    for obs in e['observations']:
        if now-obs['at'] > 600 or obs['social'] <= 75 or e['cooldowns'].get(obs['subject_id'], 0) > now:
            continue
        request = request_for(world, obs['request_id'])
        if request and request['outcome'] == 'open':
            candidates.append({'request_id': request['id'], 'subject_id': obs['subject_id'],
                'severity': obs['social'], 'created_at': request['created_at'], 'evidence_id': obs['id'],
                'position': list(obs['position'])})
    candidates.sort(key=lambda item: (-item['severity'], item['created_at'], item['request_id']))
    return candidates


def goal(world, c, place, position, reason):
    from backend.citizens import remember
    c['goal'] = {'id': str(uuid.uuid4()), 'place': place, 'position': list(position),
                 'reason': reason, 'started_at': world['clock_seconds']}
    c.update(activity='travelling', navigation='TRAVELLING', last_decision_at=world['clock_seconds'])
    remember(c, world['clock_seconds'], 'decision', 'Go to '+place+' ('+reason+')')


def approach(c,position,side=False):
    delta=[c['position'][i]-position[i] for i in range(3)]
    if side:delta[0],delta[2]=-delta[2],delta[0]
    length=math.hypot(delta[0],delta[2]);result=list(position)
    if length>.001:
        for i in (0,2):result[i]+=delta[i]/length*1.2
    else:result[0]+=1.2
    result[0]=max(-70,min(70,result[0]));result[2]=max(-65,min(110,result[2]))
    return result


def start_assist(world,c,selected,items,reason):
    from backend.agent_policies import decision
    request=request_for(world,selected['request_id'])
    if not request or request['outcome']!='open' or request['subject_id']==c['id']:raise ValueError('Request is claimed, terminal or targets the helper itself.')
    request.update(claimant=c['id'],outcome='claimed')
    goal(world,c,'assistance',approach(c,selected['position']),'ideology')
    e=c['exceptional'];e['action']={'kind':'assist','request_id':request['id'],'subject_id':selected['subject_id'],
        'goal_id':c['goal']['id'],'elapsed':0.,'selected_at':world['clock_seconds'],
        'observed_position':list(selected['position']),'evidence_id':selected['evidence_id']}
    decision(world,c,items,selected,reason)
    emit(world,c,'selected',reason,request,[selected['evidence_id']])


def advance(world, seconds):
    if world['paused']:
        return
    now = world['clock_seconds']; people = {c['id']: c for c in world['citizens']}
    for c in world['citizens']:
        if not active(c) or c['intervention']:
            continue
        e = c['exceptional']
        observe(world, c)
        action = e['action']
        # Recover urgently, with the same finish-recovery hysteresis as ordinary agents.
        recovery = c['goal']['reason'] == 'need' and ((c['goal']['place']=='home' and c['needs']['energy']<80) or (c['goal']['place']=='food' and c['needs']['hunger']>20))
        urgent = 'home' if c['needs']['energy']<=10 else ('food' if c['needs']['hunger']>=90 else None)
        if recovery or urgent:
            if action:finish(world, c, 'interrupted', 'Urgent physiological recovery takes priority over assistance.')
            if urgent and (c['goal']['place'] != urgent or c['goal']['reason'] != 'need'):
                goal(world,c,urgent,c['known_places'][urgent]['position'],'need')
            continue
        from backend.agent_policies import advance_contact, project_refresh
        if e['behavior_stage']=='martyr':project_refresh(world,c)
        if advance_contact(world,c,seconds):continue
        if action and action['kind'] == 'assist':
            request = request_for(world, action['request_id']); subject = people.get(action['subject_id'])
            if not request or request['outcome'] != 'claimed' or request['claimant'] != c['id']:
                e['action'] = None;continue
            if c['goal']['id'] != action['goal_id']:
                finish(world,c,'interrupted','Assistance goal was replaced.');continue
            if now-action['selected_at'] > 600:
                finish(world,c,'expired','Assistance evidence expired; revisit before acting.');continue
            if c['navigation'] == 'WAITING FOR ROUTE':
                finish(world,c,'blocked','Route failed; retry this person after a 60-second cooldown.');continue
            if c['navigation'] != 'ARRIVED':
                action['elapsed'] = 0;continue
            if not subject or not nearby({'position': action['observed_position']},subject,2):
                finish(world,c,'departed','Recipient left the observed meeting point; no assistance effect.');continue
            if not nearby(c,subject,2):
                finish(world,c,'departed','Recipient is out of interaction range; no assistance effect.');continue
            if subject['activity']=='travelling' or subject['navigation']!='ARRIVED' or subject['intervention'] is not None or subject['needs']['hunger']>=90 or subject['needs']['energy']<=10:
                finish(world,c,'declined','Recipient is busy, directed or needs urgent care; offer declined.');continue
            if subject['needs']['social']<=75:
                finish(world,c,'expired','Observed need has resolved; no assistance effect.');continue
            # Every dwell interval requires fresh, accepted physical records from both bodies.
            freshness = max(2, world['time_scale']*2)
            if now-c.get('physical_at',-1e9)>freshness or now-subject.get('physical_at',-1e9)>freshness:
                action['elapsed']=0;continue
            action['elapsed'] += seconds
            c['activity'] = 'assisting'
            if action['elapsed'] >= 5:
                before = subject['needs']['social'];after = max(0,before-5)
                subject['needs']['social'] = after
                request.update(outcome='completed',closed_at=now)
                e['cooldowns'][subject['id']] = now+60
                e['cooldowns'] = dict(sorted(e['cooldowns'].items(),key=lambda item:item[1])[-16:])
                trust(c,subject['id'],1)
                from backend.citizens import remember
                remember(subject,now,'interaction','Voluntary social assistance from '+c['name'])
                emit(world,c,'completed','Physical voluntary assistance completed once; social need reduced by 5.',request,[action['evidence_id']],before,after)
                e['action']=None
            continue
        if action and action['kind']=='observe' and c['navigation']=='ARRIVED' and action['elapsed']<15:
            from backend.city_life import OBSERVATION_RATES
            rate=OBSERVATION_RATES.get(e['profile'],1.0)  # Profile-specific dwell; elapsed stays bounded to 15.
            if now-c.get('physical_at',-1e9)<=max(2,world['time_scale']*2):action['elapsed']=min(15,action['elapsed']+seconds*rate)
            continue
        from backend.agent_policies import select
        if select(world,c,choose(world,c)):continue
        if not action or c['navigation']=='ARRIVED' or c['navigation']=='WAITING FOR ROUTE':
            # Deterministic visits to own known public points provide new local evidence.
            # Each profile walks its own route through its own quarter of the district.
            from backend.city_life import OBSERVATION_CYCLES
            cycle = OBSERVATION_CYCLES.get(e['profile'], ('park','food','home'))
            previous = c['goal']['place']
            place = cycle[(cycle.index(previous)+1) % len(cycle)] if previous in cycle else cycle[0]
            goal(world,c,place,c['known_places'][place]['position'],'ideology')
            e['action']={'kind':'observe','request_id':None,'subject_id':None,'goal_id':c['goal']['id'],
                         'elapsed':0.,'selected_at':now,'observed_position':None,'evidence_id':None}
            e['decision']={'at':now,'reason':'No eligible observed request; visit a known place to observe locally.','candidates':[], 'selected_request':None}
            emit(world,c,'selected',e['decision']['reason'])


def validate(world):
    """Validate bounded durable behavior state without running any behavior."""
    from backend.store import number, vector
    ids = {c['id'] for c in world['citizens']}
    agents = {c['id']:c for c in world['citizens'] if c['kind']=='exceptional'}
    now = world['clock_seconds']
    def identifier(value):
        uuid.UUID(value)
    def position(value):
        vector(value, ((-70,70),(-.5,18),(-65,110)))
    requests = world['assistance_requests']; history = world['agent_history']
    if not isinstance(requests,list) or len(requests)>64 or not isinstance(history,list) or len(history)>64:
        raise ValueError('Unbounded agent requests/history.')
    seen = set(); open_subjects = set()
    for r in requests:
        if set(r)!={'id','subject_id','created_at','severity','claimant','outcome','closed_at'}:raise ValueError('Invalid request fields.')
        identifier(r['id'])
        if r['id'] in seen or r['subject_id'] not in ids or r['outcome'] not in TERMINAL|{'open','claimed'}:raise ValueError('Invalid request identity/outcome.')
        seen.add(r['id']);number(r['created_at'],0,now);number(r['severity'],0,100)
        if r['claimant'] is not None and r['claimant'] not in agents:raise ValueError('Invalid request claimant.')
        if r['outcome'] in {'open','claimed'}:
            if r['subject_id'] in open_subjects or r['closed_at'] is not None:raise ValueError('Duplicate active request.')
            open_subjects.add(r['subject_id'])
            if (r['outcome']=='open') != (r['claimant'] is None):raise ValueError('Invalid active claim.')
        else:number(r['closed_at'],r['created_at'],now)
    event_ids = set()
    for event in history:
        identifier(event['id'])
        if event['id'] in event_ids or event['agent_id'] not in agents or event['outcome'] not in TERMINAL|{'observed','selected','verified','coordinated','project'}:raise ValueError('Invalid agent event.')
        event_ids.add(event['id']);number(event['at'],0,now)
        if not isinstance(event['detail'],str) or len(event['detail'])>512:raise ValueError('Invalid event detail.')
        if event['subject_id'] is not None and event['subject_id'] not in ids:raise ValueError('Unknown event subject.')
        if not isinstance(event['evidence'],list) or len(event['evidence'])>16:raise ValueError('Unbounded event evidence.')
        for value in event['evidence']:identifier(value)
        if event['request_id'] is not None:identifier(event['request_id'])
        fact=event.get('fact')
        if fact is not None:
            if event['outcome']!='verified' or set(fact)!={'at','social','source_id'} or fact['source_id']!=event['subject_id']:raise ValueError('Invalid verified fact audit.')
            number(fact['at'],0,event['at']);number(fact['social'],0,100)
        if event['outcome']=='completed':
            number(event['before_social'],0,100);number(event['after_social'],0,100)
            if abs(event['before_social']-event['after_social']-5)>1e-9:raise ValueError('Invalid assistance effect.')
    for c in agents.values():
        e=c['exceptional'];observations=e['observations'];cooldowns=e['cooldowns']
        if not isinstance(observations,list) or len(observations)>16 or len({o.get('subject_id') for o in observations})!=len(observations):raise ValueError('Invalid bounded observations.')
        for o in observations:
            if set(o)!={'id','subject_id','at','source','social','position','request_id'} or o['subject_id'] not in ids or o['subject_id']==c['id'] or not (o['source']=='local_proximity' or (isinstance(o['source'],str) and o['source'].startswith('coordination:') and o['source'].split(':',1)[1] in agents and o['source'].split(':',1)[1]!=c['id'])):raise ValueError('Invalid local evidence.')
            identifier(o['id']);number(o['at'],0,now);number(o['social'],0,100);position(o['position'])
            if o['request_id'] is not None:identifier(o['request_id'])
        if not isinstance(cooldowns,dict) or len(cooldowns)>16:raise ValueError('Unbounded cooldowns.')
        for target, expiry in cooldowns.items():
            if target not in ids or target==c['id']:raise ValueError('Invalid cooldown target.')
            number(expiry,0,now+60)
        number(e['next_observation_at'],0,now+5)
        info=e['information']
        if not isinstance(info,dict) or len(info)>16 or (e['behavior_stage']!='attendant' and info):raise ValueError('Invalid bounded information.')
        for target,fact in info.items():
            if target not in ids or target==c['id'] or set(fact)!={'at','social','source_id'} or fact['source_id']!=target:raise ValueError('Invalid verified source.')
            number(fact['at'],0,now);number(fact['social'],0,100)
        project=e['project']
        if project is not None:
            if e['behavior_stage']!='martyr' or set(project)!={'id','created_at','status','request_ids','outcomes','partner_id','delegated_request_id'}:raise ValueError('Only Martyr owns a bounded civic project.')
            identifier(project['id']);number(project['created_at'],0,now)
            if not isinstance(project['request_ids'],list) or not 1<=len(project['request_ids'])<=16 or len(set(project['request_ids']))!=len(project['request_ids']):raise ValueError('Invalid project requests.')
            for value in project['request_ids']:identifier(value)
            if project['status'] not in {'active','delegated','completed'} or not isinstance(project['outcomes'],dict) or not set(project['outcomes']).issubset(project['request_ids']) or any(outcome not in TERMINAL for outcome in project['outcomes'].values()):raise ValueError('Invalid project outcomes.')
            if project['status']=='delegated':
                if project['partner_id'] not in agents or project['partner_id']==c['id'] or project['delegated_request_id'] not in project['request_ids']:raise ValueError('Invalid delegated project.')
            elif project['partner_id'] is not None or project['delegated_request_id'] is not None:raise ValueError('Orphan project delegation.')
        action=e['action']
        if action is not None:
            if set(action)!={'kind','request_id','subject_id','goal_id','elapsed','selected_at','observed_position','evidence_id'} or action['kind'] not in {'observe','assist','inspect','coordinate'}:raise ValueError('Invalid bounded action.')
            if action['goal_id']!=c['goal']['id'] or c['intervention'] is not None:raise ValueError('Action cannot override current authority.')
            number(action['elapsed'],0,15 if action['kind']=='observe' else 5);number(action['selected_at'],0,now)
            if action['kind']=='assist':
                r=request_for(world,action['request_id'])
                if not r or r['outcome']!='claimed' or r['claimant']!=c['id'] or r['subject_id']!=action['subject_id'] or c['goal']['place']!='assistance' or math.dist(c['goal']['position'],action['observed_position'])>1.201:raise ValueError('Action must own its physical request goal.')
                position(action['observed_position']);identifier(action['evidence_id'])
            elif action['kind'] in {'inspect','coordinate'}:
                if action['subject_id'] not in ids or action['subject_id']==c['id'] or c['goal']['place']!='contact' or math.dist(c['goal']['position'],action['observed_position'])>1.201:raise ValueError('Invalid physical contact goal.')
                position(action['observed_position']);identifier(action['evidence_id'])
                if action['kind']=='inspect' and (e['behavior_stage']!='attendant' or action['request_id'] is not None):raise ValueError('Only Attendant verifies information.')
                if action['kind']=='coordinate':
                    if e['behavior_stage'] not in {'attendant','martyr'} or action['subject_id'] not in agents:raise ValueError('Coordination requires voluntary Exceptional peers.')
                    identifier(action['request_id'])
            elif any(action[k] is not None for k in ('request_id','subject_id','observed_position','evidence_id')):raise ValueError('Observation action has no remote recipient.')
    for decision in [e.get('decision') for e in history]+[c['exceptional']['decision'] for c in agents.values()]:
        if decision is not None:
            if set(decision) not in ({'at','reason','candidates','selected_request'},{'at','reason','candidates','selected_request','selected_target'}) or not isinstance(decision['reason'],str) or len(decision['reason'])>512 or not isinstance(decision['candidates'],list) or len(decision['candidates'])>16:raise ValueError('Invalid bounded decision.')
            number(decision['at'],0,now)
            for item in decision['candidates']:
                if not {'request_id','subject_id','severity','created_at','evidence_id','position'}<=set(item) or set(item)-{'request_id','subject_id','severity','created_at','evidence_id','position','trust','verified_at'} or item['subject_id'] not in ids:raise ValueError('Invalid decision candidate.')
                
                if item['request_id'] is not None:identifier(item['request_id'])
                identifier(item['evidence_id']);position(item['position']);number(item['severity'],0,100);number(item['created_at'],0,decision['at'])
                if 'trust' in item:number(item['trust'],-100,100)
                if item.get('verified_at') is not None:number(item['verified_at'],0,decision['at'])
            if decision.get('selected_target') is not None and decision['selected_target'] not in {i['subject_id'] for i in decision['candidates']}:raise ValueError('Selected contact lacks local evidence.')
            if decision['selected_request'] is not None and decision['selected_request'] not in {i['request_id'] for i in decision['candidates']}:raise ValueError('Selection lacks local evidence.')
    for r in requests:
        if r['outcome']=='claimed':
            action=agents[r['claimant']]['exceptional']['action']
            if not action or action['request_id']!=r['id']:raise ValueError('Orphan assistance claim.')
