"""Explicit destination-only authority over civilians, police and Exceptional Agents."""
from copy import deepcopy
import uuid

HISTORY_LIMIT = 64


def migrate(world):
    world.setdefault('intervention_history', [])
    for c in world['citizens']:
        c.setdefault('intervention', None)


def record(world, command_id, target, action, outcome, reason, before, after, message):
    event = {'id': str(uuid.uuid4()), 'command_id': command_id, 'citizen_id': target,
             'actor': 'Brother Eye' if action != 'navigation' else 'physical_navigation',
             'action': action, 'outcome': outcome, 'reason': reason,
             'at': world['clock_seconds'], 'before': deepcopy(before),
             'after': deepcopy(after), 'message': message}
    world['intervention_history'].append(event)
    world['intervention_history'] = world['intervention_history'][-HISTORY_LIMIT:]
    return event


def context(c):
    return {'goal': deepcopy(c['goal']), 'intervention': deepcopy(c.get('intervention'))}


def apply(world, payload, command_id):
    """Validate first; caller runs on a detached world and commits state+audit+receipt."""
    if set(payload) != {'world_id', 'citizen_id', 'expected_goal_id', 'expected_intervention_id', 'action', 'place', 'reason'}:
        raise ValueError('Invalid intervention fields.')
    reason = payload['reason']
    if not isinstance(reason, str) or not reason.strip() or len(reason) > 240 or any(ord(ch) < 32 for ch in reason):
        raise ValueError('Provide a reason of 1–240 printable characters.')
    if payload['world_id'] != world['world_id']:
        raise ValueError('This command belongs to a different city.')
    c = next((c for c in world['citizens'] if c['id'] == payload['citizen_id']), None)
    if c is None or c.get('kind') not in {'civilian', 'police', 'exceptional'}:
        raise ValueError('Only an existing civilian, police resident or Exceptional Agent may be directed.')
    active = c.get('intervention')
    if payload['expected_goal_id'] != c['goal']['id'] or payload['expected_intervention_id'] != (active['id'] if active else None):
        raise ValueError('The resident goal or override changed. Review the current state and try again.')
    action = payload['action']
    if action not in {'assign_destination', 'release'}:
        raise ValueError('Unsupported intervention action.')
    if action == 'assign_destination' and (not isinstance(payload['place'], str) or payload['place'] not in c['known_places']):
        raise ValueError('Destination must be a place this resident already knows.')
    if action == 'release' and (payload['place'] is not None or active is None):
        raise ValueError('Release requires an existing override and no destination.')
    before = context(c)
    from backend.agent_behavior import interrupt
    interrupt(world, c)
    if active:
        record(world, active['id'], c['id'], 'superseded' if action == 'assign_destination' else 'release',
               'superseded' if action == 'assign_destination' else 'released', reason.strip(), before, None,
               'Previous override ended by command '+command_id)
    if action == 'assign_destination':
        place = payload['place']
        c['intervention'] = {'id': command_id, 'place': place, 'reason': reason.strip(),
                             'issued_at': world['clock_seconds'], 'status': 'travelling'}
        c['goal'] = {'id': str(uuid.uuid4()), 'place': place, 'reason': 'intervention',
                     'position': list(c['known_places'][place]['position']), 'started_at': world['clock_seconds']}
        c['activity'], c['navigation'] = 'travelling', 'TRAVELLING'
        message = 'Destination override accepted; held until explicitly released. Arrival requires physical travel.'
    else:
        from backend.citizens import plan
        c['intervention'] = None
        # Force a fresh goal even if autonomous planning chooses the same place.
        c['goal'] = None
        plan(c, world['clock_seconds'])
        message = 'Override released; autonomous needs and schedule resumed.'
    c['last_decision_at'] = world['clock_seconds']
    from backend.citizens import remember
    remember(c, world['clock_seconds'], 'intervention', action+': '+reason.strip())
    record(world, command_id, c['id'], action, 'accepted', reason.strip(), before, context(c), message)
    return {'id': command_id, 'outcome': 'accepted', 'message': message, 'citizen_id': c['id']}


def reject(world, payload, command_id, message):
    # Bound untrusted audit text; reject without changing a resident, then durably receipt it.
    target = str(payload.get('citizen_id', ''))[:80]
    record(world, command_id, target, str(payload.get('action', ''))[:40], 'rejected',
           str(payload.get('reason', ''))[:240], None, None, message)
    return {'id': command_id, 'outcome': 'rejected', 'message': message, 'citizen_id': target}


def navigation(world, c):
    active = c.get('intervention')
    if not active:
        return
    status = {'ARRIVED': 'completed', 'WAITING FOR ROUTE': 'waiting_for_route',
              'WAITING FOR SPACE': 'waiting_for_space'}.get(c['navigation'], 'travelling')
    if status != active['status']:
        before = context(c)
        active['status'] = status
        record(world, active['id'], c['id'], 'navigation', status, active['reason'], before, context(c),
               'Physical arrival confirmed; override remains held.' if status == 'completed' else c['navigation'])


def validate(world):
    history = world.get('intervention_history')
    if not isinstance(history, list) or len(history) > HISTORY_LIMIT:
        raise ValueError('Invalid intervention history.')
    for event in history:
        uuid.UUID(event['id']); uuid.UUID(event['command_id'])
        if event['outcome'] not in {'accepted', 'rejected', 'superseded', 'released', 'completed', 'waiting_for_route', 'waiting_for_space', 'travelling'}:
            raise ValueError('Invalid intervention outcome.')
    for c in world['citizens']:
        if 'intervention' not in c:
            raise ValueError('Missing intervention state.')
        active = c['intervention']
        if active is None:
            if c['goal']['reason'] == 'intervention': raise ValueError('Orphan override goal.')
            continue
        uuid.UUID(active['id'])
        if set(active) != {'id','place','reason','issued_at','status'} or active['place'] != c['goal']['place'] or c['goal']['reason'] != 'intervention':
            raise ValueError('Invalid intervention goal.')
        if active['status'] not in {'travelling','completed','waiting_for_route','waiting_for_space'}:
            raise ValueError('Invalid intervention status.')
        if not isinstance(active['reason'],str) or not 1 <= len(active['reason']) <= 240:
            raise ValueError('Invalid intervention reason.')
        from backend.store import number
        number(active['issued_at'],0,world['clock_seconds'])
