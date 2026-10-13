"""Bounded policy choices and voluntary local coordination; no external AI or authority."""
from copy import deepcopy
import math
import uuid

STAGES={'arbiter_of_dawn':'arbiter','attendant_of_mysteries':'attendant',
        'martyr_of_providence':'martyr','sovereign_of_unbound_will':'sovereign'}


def migrate(world):
    for c in world['citizens']:
        if c['kind']!='exceptional':continue
        e=c['exceptional'];e['behavior_stage']=STAGES[e['profile']];e['information']={}


def candidates(world,c):
    """Use only the actor's evidence; static identity lookups never expose another brain."""
    from backend import agent_behavior as b
    e=c['exceptional'];now=world['clock_seconds'];result=[]
    for obs in e['observations']:
        if now-obs['at']>600 or e['cooldowns'].get(obs['subject_id'],0)>now:continue
        result.append({'request_id':obs['request_id'],'subject_id':obs['subject_id'],
            'severity':obs['social'],'created_at':obs['at'],'evidence_id':obs['id'],
            'position':list(obs['position'])})
    return result


def information_candidates(world,c):
    e=c['exceptional'];now=world['clock_seconds']
    result=[item for item in candidates(world,c) if item['subject_id'] not in e['information'] or now-e['information'][item['subject_id']]['at']>=60]
    for item in result:
        item['trust']=e['relationships'].get(item['subject_id'],{}).get('trust',0)
        item['verified_at']=e['information'].get(item['subject_id'],{}).get('at')
    # Unverified first, then oldest verification, then experienced source reliability.
    result.sort(key=lambda item:(item['subject_id'] in e['information'],
        e['information'].get(item['subject_id'],{}).get('at',-1),
        -e['relationships'].get(item['subject_id'],{}).get('trust',0),item['subject_id']))
    return result


def partners(world,c,known_only=False):
    people={p['id']:p for p in world['citizens']};e=c['exceptional']
    items=[item for item in candidates(world,c) if people[item['subject_id']]['kind']=='exceptional'
           and (not known_only or item['subject_id'] in e['relationships'])]
    for item in items:item['trust']=e['relationships'].get(item['subject_id'],{}).get('trust',0)
    items.sort(key=lambda item:(-e['relationships'].get(item['subject_id'],{}).get('trust',0),item['subject_id']))
    return items


def decision(world,c,items,selected,reason,target=None):
    e=c['exceptional']
    e['decision']={'at':world['clock_seconds'],'reason':reason,'candidates':deepcopy(items),
                   'selected_request':selected['request_id'] if selected else None,
                   'selected_target':target or (selected['subject_id'] if selected else None)}


def start_contact(world,c,target,kind,items,reason,request_id=None):
    from backend import agent_behavior as b
    b.goal(world,c,'contact',b.approach(c,target['position'],side=True),'ideology')
    c['exceptional']['action']={'kind':kind,'request_id':request_id,'subject_id':target['subject_id'],
        'goal_id':c['goal']['id'],'elapsed':0.,'selected_at':world['clock_seconds'],
        'observed_position':list(target['position']),'evidence_id':target['evidence_id']}
    chosen=next((item for item in items if request_id is not None and item['request_id']==request_id),None)
    choices=([target]+[item for item in items if item['subject_id']!=target['subject_id']])[:16]
    decision(world,c,choices,chosen,reason,target['subject_id'])
    b.emit(world,c,'selected',reason,evidence=[target['evidence_id']],subject=target['subject_id'])


def project_refresh(world,c):
    from backend import agent_behavior as b
    p=c['exceptional']['project']
    if not p or p['status']=='completed':return
    changed=False
    for identifier in p['request_ids']:
        r=b.request_for(world,identifier)
        # An unclaimed project task cannot wait forever after its local evidence
        # expires or is evicted. Never cancel another helper's active claim.
        if r and r['outcome']=='open' and not any(o['request_id']==identifier and world['clock_seconds']-o['at']<=600 for o in c['exceptional']['observations']):
            r.update(outcome='expired',closed_at=world['clock_seconds'])
            b.emit(world,c,'expired','Unclaimed project task lost current local evidence; revisit before starting new work.',r)
        if r and r['outcome'] in b.TERMINAL and identifier not in p['outcomes']:
            p['outcomes'][identifier]=r['outcome'];changed=True
    if p['delegated_request_id'] in p['outcomes']:
        p.update(status='active',partner_id=None,delegated_request_id=None);changed=True
    if len(p['outcomes'])==len(p['request_ids']):p['status']='completed';changed=True
    if changed:b.emit(world,c,'project','Civic project updated from recorded task outcomes: '+p['status'])


def select(world,c,requests):
    """Select at most one held action. Returns whether a policy started/holds work."""
    from backend import agent_behavior as b
    e=c['exceptional'];stage=e['behavior_stage']
    if stage=='arbiter':
        if not requests:return False
        b.start_assist(world,c,requests[0],requests,'Most severe locally observed request; ties use age then stable request ID. Friendship does not change priority.')
        return True
    if stage=='sovereign':
        own=[item for item in requests if e['relationships'].get(item['subject_id'],{}).get('companion')]
        if not own:return False
        b.start_assist(world,c,own[0],requests,'Known companion before a more severe stranger; own urgent recovery still takes priority.')
        return True
    if stage=='attendant':
        uncertain=information_candidates(world,c)
        if uncertain:
            start_contact(world,c,uncertain[0],'inspect',uncertain,'Verify uncertain local information: unverified first, then oldest fact, then learned source trust.')
            return True
        contacts=partners(world,c,known_only=True)
        if requests and contacts:
            start_contact(world,c,contacts[0],'coordinate',requests,'Information is current; offer a useful observed request to the most trusted known local Exceptional contact.',requests[0]['request_id'])
            return True
        return False
    project_refresh(world,c)
    p=e['project']
    if p and p['status']=='delegated':return True
    if not p or p['status']=='completed':
        if not requests:return False
        anchor={'position':requests[0]['position']}
        cluster=[item for item in requests if b.nearby(anchor,item,8)]
        e['project']=p={'id':str(uuid.uuid4()),'created_at':world['clock_seconds'],'status':'active',
            'request_ids':[item['request_id'] for item in cluster], 'outcomes':{},
            'partner_id':None,'delegated_request_id':None}
        b.emit(world,c,'project','Created a civic project from a locally observed cluster of unmet requests.')
    remaining=[item for item in requests if item['request_id'] in p['request_ids'] and item['request_id'] not in p['outcomes']]
    if not remaining:return False
    contacts=partners(world,c)
    if contacts:
        start_contact(world,c,contacts[0],'coordinate',remaining,'Civic project: offer voluntary coordination to the most trusted observed Exceptional partner.',remaining[0]['request_id'])
    else:b.start_assist(world,c,remaining[0],remaining,'Civic project: no available voluntary partner; personally assist the next observed project request.')
    return True


def willing(world,partner,offer):
    """Partner's own policy/commitment gates the offer; civilians never enter this path."""
    from backend import agent_behavior as b
    e=partner.get('exceptional')
    if not e or offer['subject_id']==partner['id'] or e['cooldowns'].get(offer['subject_id'],0)>world['clock_seconds'] or partner['intervention'] or partner['needs']['energy']<=10 or partner['needs']['hunger']>=90:return False
    recovery=partner['goal']['reason']=='need' and ((partner['goal']['place']=='home' and partner['needs']['energy']<80) or (partner['goal']['place']=='food' and partner['needs']['hunger']>20))
    if recovery or (e['action'] and e['action']['kind']!='observe'):return False
    if e['behavior_stage']=='sovereign':return e['relationships'].get(offer['subject_id'],{}).get('companion',False)
    if e['behavior_stage']=='attendant' and information_candidates(world,partner):return False
    if e['behavior_stage']=='martyr' and e['project'] and e['project']['status']!='completed':return False
    if e['behavior_stage']=='arbiter':
        choices=b.choose(world,partner)
        if choices and (-choices[0]['severity'],choices[0]['created_at'],choices[0]['request_id'])<(-offer['severity'],offer['created_at'],offer['request_id']):return False
    return True


def advance_contact(world,c,seconds):
    """Travel and five-second physical confirmation precede information/offer effects."""
    from backend import agent_behavior as b
    e=c['exceptional'];a=e['action'];now=world['clock_seconds']
    if not a or a['kind'] not in {'inspect','coordinate'}:return False
    subject=next((p for p in world['citizens'] if p['id']==a['subject_id']),None)
    if now-a['selected_at']>600:b.finish(world,c,'expired','Local contact evidence expired.');return True
    if c['navigation']=='WAITING FOR ROUTE':b.finish(world,c,'blocked','Contact route failed; retry after cooldown.');return True
    if c['goal']['id']!=a['goal_id']:b.finish(world,c,'interrupted','Contact goal changed.');return True
    if c['navigation']!='ARRIVED':a['elapsed']=0;return True
    if not subject or not b.nearby(c,subject,2) or not b.nearby({'position':a['observed_position']},subject,2):
        b.finish(world,c,'departed','Contact left the observed meeting point.');return True
    # An idle observation visit can voluntarily accept; busy people cannot be commandeered.
    if subject['navigation']!='ARRIVED' or subject['activity']=='travelling' or subject['intervention'] or subject['needs']['energy']<=10 or subject['needs']['hunger']>=90:
        b.finish(world,c,'declined','Local contact is busy, directed or urgently recovering.');return True
    if now-c.get('physical_at',-1e9)>max(2,world['time_scale']*2) or now-subject.get('physical_at',-1e9)>max(2,world['time_scale']*2):a['elapsed']=0;return True
    a['elapsed']+=seconds;c['activity']='conferring'
    if a['elapsed']<5:return True
    if a['kind']=='inspect':
        e['information'][subject['id']]={'at':now,'social':subject['needs']['social'],'source_id':subject['id']}
        e['information']=dict(sorted(e['information'].items(),key=lambda item:(item[1]['at'],item[0]))[-16:])
        b.trust(c,subject['id'],1)
        from backend.citizens import remember
        remember(subject,now,'interaction','Voluntary local information exchange with '+c['name'])
        b.emit(world,c,'verified','Physically verified a local social-need fact; source trust +1. No social reward.',evidence=[a['evidence_id']],subject=subject['id'],fact=e['information'][subject['id']])
        b.cooldown(world,c,subject['id']);e['action']=None
        return True
    request=b.request_for(world,a['request_id'])
    obs=next((o for o in e['observations'] if o['request_id']==a['request_id'] and now-o['at']<=600),None)
    if not request or request['outcome']!='open' or not obs:
        b.finish(world,c,'expired','Offered request is no longer open or its evidence expired.');return True
    offer={'request_id':request['id'],'subject_id':obs['subject_id'],'severity':obs['social'],
           'created_at':request['created_at'],'position':list(obs['position']),'evidence_id':obs['id']}
    if not willing(world,subject,offer):b.finish(world,c,'declined','Exceptional partner declined under their own policy or commitment.');return True
    # Explicit physical communication shares just this fact, with original observation time.
    received=deepcopy(obs);received['source']='coordination:'+c['id']
    subject['exceptional']['observations']=[o for o in subject['exceptional']['observations'] if o['subject_id']!=obs['subject_id']]+[received]
    subject['exceptional']['observations']=subject['exceptional']['observations'][-16:]
    b.start_assist(world,subject,offer,[offer],'Voluntarily accepted a physically offered request consistent with own policy; evidence source '+c['name']+'.')
    b.trust(c,subject['id'],1);b.trust(subject,c['id'],1)
    b.emit(world,c,'coordinated','Voluntary offer accepted; one helper owns the request. No assistance reward until helper physical completion.',request,[obs['id']])
    if e['project'] and request['id'] in e['project']['request_ids']:
        e['project'].update(status='delegated',partner_id=subject['id'],delegated_request_id=request['id'])
    b.cooldown(world,c,subject['id']);e['action']=None
    return True
