"""Durable routines with local place knowledge; movement is confirmed by Godot."""
from copy import deepcopy
import math
import uuid

PLACES = {
    'home': {'name': 'Residential promenade', 'position': [18, .12, 90]},
    'work': {'name': 'Observatory terrace', 'position': [34, 12, 8]},
    'food': {'name': 'Market promenade', 'position': [18, .12, -14]},
    'park': {'name': 'Uplink plaza', 'position': [10, .12, -40]},
}
ACTIVITIES = {'home': 'resting', 'work': 'working', 'food': 'eating', 'park': 'socializing', 'assistance': 'assisting', 'contact': 'conferring'}
SCHEDULE = [{'hour': 0, 'place': 'home'}, {'hour': 8, 'place': 'work'},
            {'hour': 12, 'place': 'food'}, {'hour': 13, 'place': 'work'},
            {'hour': 17, 'place': 'park'}, {'hour': 19, 'place': 'home'}]


def remember(citizen, clock, kind, detail):
    citizen['memory'].append({'at': clock, 'kind': kind, 'detail': detail})
    citizen['memory'] = citizen['memory'][-16:]


def seed_citizens(world):
    citizen = {
        'id': str(uuid.uuid5(uuid.UUID(world['world_id']), 'civilian-001')),
        'name': 'Alex Vale', 'role': 'Observatory technician',
        'position': [18, .12, 90], 'yaw': 0.0, 'motion_seq': 0,
        'needs': {'hunger': 18.0, 'energy': 82.0, 'social': 35.0},
        'known_places': deepcopy(PLACES), 'schedule': deepcopy(SCHEDULE),
        'goal': None, 'activity': 'resting', 'navigation': 'ARRIVED',
        'memory': [], 'last_decision_at': world['clock_seconds'],
    }
    world['citizens'] = [citizen]
    plan(citizen, world['clock_seconds'])



ORDINARY_POPULATION_SIZE = 30
POPULATION_SIZE = 34
TIER1_POPULATION_SIZE = 50
TIER2_POPULATION_SIZE = 100
POPULATION_SIZES = (34, 50, 100)
NAMES = ["Alex Vale", "Mira Chen", "Jonah Reed", "Leila Noor", "Theo Park", "Nia Brooks",
         "Eli Santos", "Ada Lin", "Omar Hale", "Iris Quinn", "Noah Voss", "Sana Mercer",
         "Leo Okafor", "Zoe Kim", "Arun Shah", "Maya Ellis", "Finn Cole", "Esme Ward",
         "Kai Morgan", "Lena Cruz", "Sam Rowan", "Imani Wells", "Luca Gray", "Rina Moss",
         "Jules Ames", "Officer Vega", "Officer Arden", "Officer Sato", "Officer Bell", "Officer Kaur"]
TIER1_NAMES = [
    "Talia Vance", "Damon Cross", "Lyra Sterling", "Corin Holt",
    "Nadia Reyes", "Silas Drake", "Priya Nair", "Kaelen Mercer",
    "Freya Lind", "Tobias Finch", "Aria Solis", "Felix Vance",
    "Cassian Vale", "Meera Thorne", "Julian Frost", "Orla Bennett"
]
TIER2_NAMES = [f'{first} {last}' for first in ('Avery', 'Rowan', 'Soren', 'Amara', 'Quinn', 'Dara', 'Cleo', 'Idris', 'Nova', 'Remy') for last in ('Ash', 'Quill', 'Marin', 'Solano', 'Keene')]
ROLES = ['Transit worker', 'Market vendor', 'Civic engineer', 'Medical worker', 'Resident']


def expand_tier1(world):
    """Append 16 residents, preserving the original 34 verbatim."""
    _expand(world, 1)

def expand_tier2(world):
    """Append 50 residents, preserving the original 50 verbatim."""
    _expand(world, 2)

def _expand(world, tier):
    baseline, names = (34, TIER1_NAMES) if tier == 1 else (50, TIER2_NAMES)
    if len(world['citizens']) != baseline:
        raise ValueError(f'Tier {tier} expansion requires exactly {baseline} residents.')
    if any(c['name'] in names for c in world['citizens']):
        raise ValueError('Residents already expanded.')
    preserved={c['id'] for c in world['citizens']}
    for idx, name in enumerate(names):
        i = baseline + idx
        side = -1 if idx % 2 else 1
        slot = idx // 2
        x = side * (14.0 + (slot % 3) * 2.2)
        places = {
            'home': {'name': 'Residential promenade', 'position': [x, .12, 50.0 + (slot // 3) * 4.5]},
            'work': {'name': 'Observatory terrace', 'position': [side * (34.0 + (slot % 3) * 3.5), 12.0, -4.0 + (slot // 3) * 3.0]},
            'food': {'name': 'Market promenade', 'position': [x, .12, -16.0 + (slot // 3) * 3.5]},
            'park': {'name': 'Uplink plaza', 'position': [x, .12, -44.0 + (slot // 3) * 3.5]},
        }
        schedule = deepcopy(SCHEDULE)
        if idx % 3 == 1: schedule[1]['hour'] = 7
        if idx % 3 == 2: schedule[1]['hour'] = 9
        spawn = places[['home', 'food', 'park'][idx % 3]]['position']
        c = {
            'id': str(uuid.uuid5(uuid.UUID(world['world_id']), f'civilian-{i+1:03d}')),
            'name': name,
            'role': ROLES[idx % len(ROLES)],
            'kind': 'civilian',
            'appearance': idx % 8,
            'position': list(spawn),
            'yaw': 0.0,
            'motion_seq': 0,
            'needs': {'hunger': float(14 + idx % 7 * 4), 'energy': float(68 + idx % 6 * 4), 'social': float(22 + idx % 5 * 8)},
            'known_places': places,
            'schedule': schedule,
            'goal': None,
            'activity': 'resting',
            'navigation': 'ARRIVED',
            'memory': [],
            'last_decision_at': world['clock_seconds'],
            'intervention': None,
        }
        world['citizens'].append(c)
        plan(c, world['clock_seconds'])
    from backend.city_life import disperse, stagger, retarget
    disperse(world, preserve_ids=preserved, extended_market=tier == 2)
    stagger(world, preserve_ids=preserved)
    for idx in range(len(names)):
        c = world['citizens'][baseline + idx]
        spawn = ['home', 'food', 'park'][idx % 3]
        c['position'] = list(c['known_places'][spawn]['position'])
    retarget({'citizens':world['citizens'][baseline:], 'clock_seconds':world['clock_seconds']})
    world['population_tier'] = tier
    world['revision'] += 1



def expand_population(world):
    """Schema 3 migration preserves Alex and adds deterministic, durable residents once."""
    first = world['citizens'][0]
    first.setdefault('kind', 'civilian')
    first.setdefault('appearance', 0)
    if len(world['citizens']) != 1:
        raise ValueError('Population migration requires the Stage 3D resident.')
    for i in range(1, ORDINARY_POPULATION_SIZE):
        side = -1 if i % 2 else 1
        slot = (i-1)//2
        x = side*(14.5+(slot % 3)*2)
        places = {
            'home': {'name': 'Residential promenade', 'position': [x, .12, 88+(slot//3)*4]},
            'work': {'name': 'Observatory terrace', 'position': [side*(32+(slot % 3)*4), 12, 9+(slot//3)*3]},
            'food': {'name': 'Market promenade', 'position': [x, .12, -18+(slot//3)*3]},
            'park': {'name': 'Uplink plaza', 'position': [x, .12, -48+(slot//3)*3]},
        }
        police = i >= 25
        if police:
            patrol_slot = i-25
            # Five separate walking lanes/stop positions keep patrols distributed.
            for key, z in [('patrol_a', 66), ('patrol_b', 30), ('patrol_c', -8)]:
                places[key] = {'name': 'District patrol / '+key[-1].upper(),
                               'position': [(-1 if patrol_slot%2 else 1)*(14.5+(patrol_slot//2)*2), .12, z]}
        schedule = deepcopy(SCHEDULE)
        if i % 3 == 1: schedule[1]['hour'] = 7
        if i % 3 == 2: schedule[1]['hour'] = 9
        spawn = places[['home','food','park'][i%3]]['position'] if not police else places['patrol_b']['position']
        c = {
            'id': str(uuid.uuid5(uuid.UUID(world['world_id']), f'civilian-{i+1:03d}')),
            'name': NAMES[i], 'role': 'District police' if police else ROLES[i % len(ROLES)],
            'kind': 'police' if police else 'civilian', 'appearance': 8 if police else i%8,
            'position': list(spawn), 'yaw': 0.0, 'motion_seq': 0,
            'needs': {'hunger': float(12+i%7*5), 'energy': float(70+i%6*4), 'social': float(20+i%5*9)},
            'known_places': places, 'schedule': schedule, 'goal': None,
            'activity': 'resting', 'navigation': 'ARRIVED', 'memory': [],
            'last_decision_at': world['clock_seconds'],
        }
        world['citizens'].append(c)
        plan(c, world['clock_seconds'])


def plan(c, clock):
    if c.get('intervention') is not None:
        return  # Explicit authority holds until release, even after arrival.
    needs = c['needs']
    current = c['goal']
    # Hysteresis lets recovery finish instead of repeatedly switching activities.
    recovery = current and current['reason'] == 'need' and (
        (current['place'] == 'home' and needs['energy'] < 80) or
        (current['place'] == 'food' and needs['hunger'] > 20) or
        (current['place'] == 'park' and needs['social'] > 25))
    if recovery:
        return
    hour = ((clock + 8*3600 - c.get('routine_offset', 0)*60) % 86400) / 3600
    place = 'home'
    for entry in c['schedule']:
        if hour >= entry['hour']:
            place = entry['place']
    if c.get('kind') == 'police' and place == 'work':
        place = ('patrol_a', 'patrol_b', 'patrol_c')[int(clock//600) % 3]
    reason = 'schedule'
    if needs['energy'] < 20: place, reason = 'home', 'need'
    elif needs['hunger'] > 70: place, reason = 'food', 'need'
    elif needs['social'] > 75: place, reason = 'park', 'need'
    if place not in c['known_places']:
        return  # No access to other people's knowledge or unknown destinations.
    from backend.city_life import spot_goal, stroll
    if current and current['place'] == place:
        current['reason'] = reason
        stroll(c, clock)  # Linger, then wander to another of one's own spots at the same venue.
        return
    c['goal'] = spot_goal(c, place, reason, clock)
    c['activity'] = 'travelling'
    c['navigation'] = 'TRAVELLING'
    c['last_decision_at'] = clock
    remember(c, clock, 'decision', f"Go to {place} ({reason})")


def advance_citizens(world, seconds):
    if seconds <= 0: return
    for c in world['citizens']:
        n = c['needs']
        n['hunger'] = min(100, max(0, n['hunger'] + seconds*(-.15 if c['activity']=='eating' else .0025)))
        n['energy'] = min(100, max(0, n['energy'] + seconds*(.025 if c['activity']=='resting' else -.0025)))
        n['social'] = min(100, max(0, n['social'] + seconds*(-.03 if c['activity']=='socializing' else .0015)))
        from backend.agent_behavior import active
        if not active(c):
            plan(c, world['clock_seconds'])


def progress(world, payload):
    if not isinstance(payload, dict): raise ValueError('Invalid citizen progress.')
    c = next((c for c in world['citizens'] if c['id']==payload.get('citizen_id')), None)
    if c is None: raise ValueError('Unknown citizen identity.')
    seq = payload.get('seq')
    # Godot's JSON journal parser represents every JSON number as a float.
    # Accept exact integral values on replay, while rejecting fractions/bools.
    if isinstance(seq,bool) or not isinstance(seq,(int,float)) or not math.isfinite(seq) or not 1<=seq<=2**53-1 or int(seq)!=seq:
        raise ValueError('Invalid movement sequence.')
    seq = int(seq)
    pos = payload.get('position')
    if not isinstance(pos, list) or len(pos)!=3: raise ValueError('Invalid citizen position.')
    limits = [(-70,70),(-.5,18),(-65,110)]
    for value, (lo, hi) in zip(pos, limits):
        if isinstance(value, bool) or not isinstance(value,(float,int)) or not math.isfinite(value) or not lo<=value<=hi:
            raise ValueError('Citizen position outside the navigable district.')
    yaw = payload.get('yaw')
    if isinstance(yaw,bool) or not isinstance(yaw,(float,int)) or not math.isfinite(yaw) or abs(yaw)>1e6:
        raise ValueError('Invalid citizen heading.')
    state = payload.get('navigation')
    if state not in {'TRAVELLING','WAITING FOR ROUTE','ARRIVED','IDLE','WAITING FOR SPACE'}: raise ValueError('Invalid navigation state.')
    if payload.get('goal_id') != c['goal']['id'] or seq <= c['motion_seq']:
        return False  # Old durable requests can be replayed without overwriting a newer task.
    if state=='ARRIVED' and math.dist(pos,c['goal']['position'])>.95:
        raise ValueError('Arrival must be at the assigned destination.')
    previous = c['navigation']
    c.update(position=list(pos), yaw=float(yaw), motion_seq=seq, navigation=state, physical_at=world['clock_seconds'])
    if state=='ARRIVED' and 'arrived_at' not in c['goal']:
        c['goal']['arrived_at'] = world['clock_seconds']  # Venue dwell is measured from real arrival.
    if state=='ARRIVED' and c['activity']=='travelling':
        c['activity'] = ACTIVITIES.get(c['goal']['place'], 'patrolling')
        remember(c,world['clock_seconds'],'arrival',c['goal']['place'])
    elif state=='WAITING FOR ROUTE' and previous!=state:
        remember(c,world['clock_seconds'],'observation','Assigned route is blocked; waiting for a usable path')
    from backend.interventions import navigation
    navigation(world, c)
    return True


def validate_citizens(citizens):
    if not isinstance(citizens, list) or len(citizens) not in POPULATION_SIZES:
        raise ValueError('Expected 34, 50 or 100 residents.')
    if len({c['id'] for c in citizens}) != len(citizens):
        raise ValueError('Duplicate citizen identity.')
    n_police = sum(c.get('kind') == 'police' for c in citizens)
    n_civilian = sum(c.get('kind') == 'civilian' for c in citizens)
    n_exceptional = sum(c.get('kind') == 'exceptional' for c in citizens)
    if n_police != 5 or n_exceptional != 4 or n_civilian != len(citizens)-9:
        raise ValueError('Expected 25, 41 or 91 civilians, 5 police and 4 Exceptional Agents.')
    for c in citizens:
        uuid.UUID(c['id']); uuid.UUID(c['goal']['id'])
        if not isinstance(c['name'],str) or not c['name'] or not isinstance(c['role'],str): raise ValueError('Invalid identity.')
        if type(c['appearance']) is not int or not 0 <= c['appearance'] <= (3 if c['kind']=='exceptional' else 8): raise ValueError('Invalid appearance.')
        if type(c['motion_seq']) is not int or c['motion_seq']<0: raise ValueError('Invalid movement sequence.')
        for value in c['needs'].values():
            if isinstance(value,bool) or not isinstance(value,(float,int)) or not math.isfinite(value) or not 0<=value<=100:
                raise ValueError('Invalid need.')
        if set(c['needs']) != {'hunger','energy','social'}: raise ValueError('Invalid needs.')
        places = c['known_places']
        required = {'home','work','food','park'} | ({'patrol_a','patrol_b','patrol_c'} if c['kind']=='police' else set())
        if set(places) != required: raise ValueError('Invalid local place knowledge.')
        from backend.city_life import validate_place, allowed_positions
        for place in places.values():
            if not isinstance(place['name'],str): raise ValueError('Invalid place name.')
            for pos in allowed_positions(place):
                if not isinstance(pos,list) or len(pos)!=3 or any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or not lo<=v<=hi for v,(lo,hi) in zip(pos,[(-70,70),(-.5,18),(-65,110)])):
                    raise ValueError('Invalid place position.')
            validate_place(place)
        if len(c['schedule']) != 6 or [e['place'] for e in c['schedule']] != [e['place'] for e in SCHEDULE]:
            raise ValueError('Invalid local schedule.')
        hours = [e['hour'] for e in c['schedule']]
        if any(type(h) is not int or not 0<=h<24 for h in hours) or hours!=sorted(set(hours)):
            raise ValueError('Invalid schedule hours.')
        offset = c.get('routine_offset', 0)
        if type(offset) is not int or not 0 <= offset < 60: raise ValueError('Invalid routine offset.')
        goal = c['goal']
        if goal.get('pose', 'stand') not in {'stand','sit'} or ('arrived_at' in goal and (isinstance(goal['arrived_at'],bool) or not isinstance(goal['arrived_at'],(int,float)) or not math.isfinite(goal['arrived_at']))):
            raise ValueError('Invalid goal posture.')
        assistance = c['goal']['place'] in {'assistance','contact'} and c.get('kind')=='exceptional' and c['goal']['reason']=='ideology'
        if not assistance and (c['goal']['place'] not in places or c['goal']['position'] not in allowed_positions(places[c['goal']['place']])):
            raise ValueError('Unknown routine destination.')
        if 'physical_at' in c and (isinstance(c['physical_at'],bool) or not isinstance(c['physical_at'],(int,float)) or not math.isfinite(c['physical_at']) or c['physical_at']<0):
            raise ValueError('Invalid physical confirmation time.')
        if c['activity'] in {'assisting','conferring'} and c.get('kind')!='exceptional':raise ValueError('Inactive assistance actor.')
        if c['activity'] not in {'travelling', 'patrolling', *ACTIVITIES.values()}:
            raise ValueError('Invalid activity.')
        if c['goal']['reason'] not in {'need','schedule','intervention','ideology'} or not isinstance(c['memory'],list) or len(c['memory'])>16:
            raise ValueError('Invalid routine memory.')
        if c['goal']['reason']=='ideology' and c.get('kind')!='exceptional':raise ValueError('Inactive ideological planner.')
        detached = deepcopy(c)
        detached['intervention'] = None
        progress({'citizens':[detached],'clock_seconds':0}, {'citizen_id':c['id'],'goal_id':c['goal']['id'],
            'seq':c['motion_seq']+1,'position':c['position'],'yaw':c['yaw'],'navigation':c['navigation']})
