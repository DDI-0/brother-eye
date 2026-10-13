"""Canonical Exceptional Agent identities, cores and bounded state."""
from copy import deepcopy
from backend.agent_policies import STAGES
import math
import uuid

PROFILES = (
    {'key': 'arbiter_of_dawn', 'name': 'Arbiter of Dawn', 'role': 'Civic arbiter',
     'core': 'Justice applies consistently, regardless of friendship or status.'},
    {'key': 'attendant_of_mysteries', 'name': 'Attendant of Mysteries', 'role': 'Information strategist',
     'core': 'Knowledge, strategy and influence are the route to power.'},
    {'key': 'martyr_of_providence', 'name': 'Martyr of Providence', 'role': 'Civic project organiser',
     'core': 'Personally bears responsibility for remaking society and sees their own plan as the necessary path.'},
    {'key': 'sovereign_of_unbound_will', 'name': 'Sovereign of Unbound Will', 'role': 'Independent companion guardian',
     'core': 'Own and inner-circle freedom comes first, even at outsiders’ expense; this is not universal altruism.'},
)
PROFILE_VERSION = 1


def migrate(world):
    """Append four once; caller commits migration and schema version atomically."""
    from backend.citizens import PLACES, SCHEDULE, plan
    if len(world['citizens']) != 30 or any(c.get('kind') == 'exceptional' for c in world['citizens']):
        raise ValueError('Exceptional Agent migration requires the original 30 residents.')
    for index, profile in enumerate(PROFILES):
        places = deepcopy(PLACES)
        places['home']['position'] = [-18-index*2, .12, 90]
        places['work']['position'] = [-32-index*2, 12, 8]
        places['food']['position'] = [-18-index*2, .12, -14]
        places['park']['position'] = [-18-index*2, .12, -40]
        relationships = {}
        if index == 3:
            # Directed existing-person bond; the companion's record is never edited.
            relationships[world['citizens'][1]['id']] = {'trust': 25, 'companion': True}
        c = {'id': str(uuid.uuid5(uuid.UUID(world['world_id']), profile['key'])),
             'name': profile['name'], 'role': profile['role'], 'kind': 'exceptional', 'appearance': index,
             'position': [-18-index*2, .12, 78], 'yaw': 0.0, 'motion_seq': 0,
             'needs': {'hunger': 18.0, 'energy': 82.0, 'social': 35.0},
             'known_places': places, 'schedule': deepcopy(SCHEDULE), 'goal': None,
             'activity': 'resting', 'navigation': 'ARRIVED', 'memory': [],
             'last_decision_at': world['clock_seconds'], 'intervention': None,
             'exceptional': {'profile': profile['key'], 'profile_version': PROFILE_VERSION,
                             'core': profile['core'], 'behavior_stage': 'foundation',
                             'observations': [], 'relationships': relationships, 'project': None}}
        world['citizens'].append(c)
        plan(c, world['clock_seconds'])


def validate(world):
    people = world['citizens']
    agents = [c for c in people if c.get('kind') == 'exceptional']
    if len(agents) != 4:
        raise ValueError('Expected four Exceptional Agents.')
    ids = {c['id'] for c in people}
    expected = {p['key']: (i, p) for i, p in enumerate(PROFILES)}
    seen = set()
    for c in people:
        if c.get('kind') != 'exceptional':
            if 'exceptional' in c:
                raise ValueError('Ordinary residents cannot acquire Exceptional Agent state.')
            continue
        state = c.get('exceptional')
        if not isinstance(state, dict) or set(state) != {'profile', 'profile_version', 'core', 'behavior_stage', 'observations', 'relationships', 'project', 'action', 'decision', 'cooldowns', 'next_observation_at', 'information'}:
            raise ValueError('Invalid Exceptional Agent foundation state.')
        key = state['profile']
        if not isinstance(key, str) or key not in expected or key in seen:
            raise ValueError('Invalid or duplicate ideological profile.')
        seen.add(key)
        index, profile = expected[key]
        if (c['id'] != str(uuid.uuid5(uuid.UUID(world['world_id']), key)) or
                c['name'] != profile['name'] or c['role'] != profile['role'] or c['appearance'] != index or
                type(state['profile_version']) is not int or state['profile_version'] != PROFILE_VERSION or
                state['core'] != profile['core'] or state['behavior_stage'] != STAGES[key]):
            raise ValueError('Exceptional Agent identity and ideological core are immutable.')
        relationships = state['relationships']
        if not isinstance(relationships, dict) or len(relationships) > 8:
            raise ValueError('Invalid bounded relationships.')
        for target, relation in relationships.items():
            if target not in ids or target == c['id'] or not isinstance(relation, dict) or set(relation) != {'trust', 'companion'}:
                raise ValueError('Invalid relationship identity.')
            trust = relation['trust']
            if isinstance(trust, bool) or not isinstance(trust, (int, float)) or not math.isfinite(trust) or not -100 <= trust <= 100 or type(relation['companion']) is not bool:
                raise ValueError('Invalid relationship value.')
        companions = [target for target, value in relationships.items() if value['companion']]
        if companions != ([people[1]['id']] if key == 'sovereign_of_unbound_will' else []):
            raise ValueError('Stage 5 companion membership is fixed.')
