"""Stage 6A organic city life.

Deterministic dispersal of every resident's local places into distinct venue *spots*,
staggered personal routines, and short in-venue strolls so nobody stands in a grid row
for hours. Pure functions over the world dict; callers commit migrations atomically.
"""
from copy import deepcopy
import hashlib
import math
import uuid

LIFE_VERSION = 1
GROUND = .12
TERRACE = 12.0
SPACING = 1.35
CLEARANCE = 1.0
MAX_SPOTS = 4

# Static district obstacles mirrored from godot/scripts/city.gd (lamps, bollards, monument, pylons, domes).
_LAMP_ZS = [-140+26*k for k in range(12)]
CIRCLES = ([(s*16.0, z, .25, GROUND) for s in (-1, 1) for z in _LAMP_ZS] +
           [(s*16.0, z+2, .4, GROUND) for s in (-1, 1) for z in _LAMP_ZS] +
           [(0.0, -40.0, 7.0, GROUND)] + [(s*12.0, 73.0, .9, GROUND) for s in (-1, 1)] +
           [(s*46.0, -2.0, 6.0, TERRACE) for s in (-1, 1)])
BENCH_ZS = (-58.0, -25.0, 82.0)
RECTS = [(lo, hi, z-1.8, z+1.8) for z in BENCH_ZS for lo, hi in ((18.4, 19.7), (-19.7, -18.4))]
EAST_HOME, WEST_HOME = (13.6, 20.4, 46.0, 108.0, GROUND), (-20.4, -13.6, 46.0, 108.0, GROUND)
EAST_FOOD, WEST_FOOD = (13.5, 20.5, -24.0, 12.0, GROUND), (-20.5, -13.5, -24.0, 12.0, GROUND)
PLAZA = (-18.5, 18.5, -56.5, -23.5, GROUND)
EAST_WORK, WEST_WORK = (30.0, 62.0, -9.0, 14.0, TERRACE), (-62.0, -30.0, -9.0, 14.0, TERRACE)
AREAS = {'home': [EAST_HOME, WEST_HOME], 'food': [EAST_FOOD, WEST_FOOD], 'park': [PLAZA], 'work': [EAST_WORK, WEST_WORK]}
# Benches: three seats each. Home seats at the residential bench, food at the market bench, park at the plaza bench.
SEAT_BENCH = {'home': 82.0, 'food': -25.0, 'park': -58.0}
SEAT_X = 17.8
# Conversation circles around the uplink monument and in the plaza corners.
GROUP_CENTERS = [(round(11.2*math.cos(math.radians(22.5+45*k)), 3), round(-40+11.2*math.sin(math.radians(22.5+45*k)), 3)) for k in range(8)] + \
                [(-12.5, -52.5), (12.5, -52.5), (-12.5, -27.5), (12.5, -27.5)]
GROUP_RADIUS = .95
# Exceptional Agents: separate quarters, so they never share a commute corridor.
EXCEPTIONAL_REGIONS = (
    {'home': [WEST_HOME], 'food': [WEST_FOOD], 'park': [(-18.5, -2.0, -56.5, -23.5, GROUND)], 'work': [WEST_WORK]},
    {'home': [EAST_HOME], 'food': [EAST_FOOD], 'park': [(2.0, 18.5, -56.5, -23.5, GROUND)], 'work': [EAST_WORK]},
    {'home': [(13.6, 20.4, 46.0, 70.0, GROUND)], 'food': [WEST_FOOD], 'park': [(-18.5, 18.5, -56.5, -47.0, GROUND)], 'work': [EAST_WORK]},
    None,  # Sovereign stays near the fixed companion's own places.
)
OBSERVATION_CYCLES = {'arbiter_of_dawn': ('park', 'food', 'home'), 'attendant_of_mysteries': ('food', 'work', 'park'),
                      'martyr_of_providence': ('park', 'work', 'food'), 'sovereign_of_unbound_will': ('home', 'park', 'food')}
# Observation dwell = 15 / rate simulated seconds; keeps the bounded 0..15 elapsed contract.
OBSERVATION_RATES = {'arbiter_of_dawn': 1.0, 'attendant_of_mysteries': .5, 'martyr_of_providence': .75, 'sovereign_of_unbound_will': .4}


def rand(*parts):
    """Deterministic uniform [0, 1) independent of Python's randomized hash()."""
    digest = hashlib.sha256('|'.join(str(p) for p in parts).encode()).digest()
    return int.from_bytes(digest[:8], 'big')/2**64


def _yaw_towards(src, dst):
    dx, dz = dst[0]-src[0], dst[1]-src[1]
    return round(math.atan2(-dx, -dz), 4)


def _clear(x, z, y, taken, clearance=CLEARANCE):
    for cx, cz, r, cy in CIRCLES:
        if abs(cy-y) < 2 and math.hypot(x-cx, z-cz) < r+clearance:
            return False
    if abs(y-GROUND) < 2:
        for x0, x1, z0, z1 in RECTS:
            if x0-clearance < x < x1+clearance and z0-clearance < z < z1+clearance:
                return False
    return all(abs(p[1]-y) > 2 or math.hypot(p[0]-x, p[2]-z) >= SPACING for p in taken)


def _sample(key, areas, taken, facing):
    for attempt in range(400):
        x0, x1, z0, z1, y = areas[int(rand(key, attempt, 'a')*len(areas))]
        x = round(x0+(x1-x0)*rand(key, attempt, 'x'), 2)
        z = round(z0+(z1-z0)*rand(key, attempt, 'z'), 2)
        if _clear(x, z, y, taken):
            taken.append([x, y, z])
            jitter = (rand(key, attempt, 'yaw')-.5)*.9
            return {'position': [x, y, z], 'pose': 'stand', 'yaw': round(facing(x, z)+jitter, 4)}
    raise ValueError('Unable to disperse a resident spot; district is over capacity.')


def _facing(place):
    if place == 'work':
        return lambda x, z: _yaw_towards((x, z), (46.0 if x > 0 else -46.0, -2.0))
    if place == 'park':
        return lambda x, z: _yaw_towards((x, z), (0.0, -40.0))
    # Promenades: face the street and its shops/foot traffic.
    return lambda x, z: _yaw_towards((x, z), (0.0, z))


def _group_spot(n, taken):
    """Slot n in the conversation circles; members face each other around the circle centre."""
    for k in range(len(GROUP_CENTERS)*4):
        index = (n+k) % (len(GROUP_CENTERS)*4)
        cx, cz = GROUP_CENTERS[index % len(GROUP_CENTERS)]
        angle = math.radians(45+90*(index//len(GROUP_CENTERS)))
        x, z = round(cx+GROUP_RADIUS*math.cos(angle), 2), round(cz+GROUP_RADIUS*math.sin(angle), 2)
        if _clear(x, z, GROUND, taken):
            taken.append([x, GROUND, z])
            return {'position': [x, GROUND, z], 'pose': 'stand', 'yaw': _yaw_towards((x, z), (cx, cz))}
    return None


def _seats():
    seats = {}
    for place, z in SEAT_BENCH.items():
        seats[place] = [{'position': [s*SEAT_X, GROUND, z+dz], 'pose': 'sit', 'yaw': round(s*math.pi/2, 4)}
                        for s in (1, -1) for dz in (-1.1, 0.0, 1.1)]
    return seats


def disperse(world, preserve_ids=(), extended_market=False):
    """Rebuild every resident's known place positions as dispersed spots. Names/keys are preserved."""
    # Tier 2 uses additional existing walkable promenade space, without changing geometry.
    food_areas = AREAS['food'] + [(13.5,20.5,14.,40.,GROUND),(-20.5,-13.5,14.,40.,GROUND)] if extended_market else AREAS['food']
    people = world['citizens']
    preserve_ids=set(preserve_ids)
    preserved=[p for c in people if c['id'] in preserve_ids for place in c['known_places'].values() for p in allowed_positions(place)]
    taken = [list(s['position']) for seats in _seats().values() for s in seats]
    taken.extend(preserved)
    # An upgrade may occur mid-commute. New spots must also clear the original
    # bodies' actual positions, without moving any existing person.
    taken.extend(list(c['position']) for c in people if c['id'] in preserve_ids)
    seats = _seats()
    ordinary = [c for c in people if c.get('kind') != 'exceptional']
    for c in ordinary:
        for patrol in ('patrol_a', 'patrol_b', 'patrol_c'):
            if patrol in c['known_places']:
                taken.append(list(c['known_places'][patrol]['position']))
    # Stable, identity-derived ordering decides who gets a bench seat and which circle.
    by_park = sorted(range(len(ordinary)), key=lambda i: rand(ordinary[i]['id'], 'park-order'))
    seat_owner = {}
    for place in ('home', 'food', 'park'):
        order = sorted(range(len(ordinary)), key=lambda i: rand(ordinary[i]['id'], place, 'seat'))
        available=[s for s in seats[place] if s['position'] not in preserved]
        order=[i for i in order if ordinary[i]['id'] not in preserve_ids]
        for seat, i in zip(available, order):
            seat_owner[(i, place)] = seat
    for i, c in enumerate(ordinary):
        if c['id'] in preserve_ids:continue
        places = c['known_places']
        rank = by_park.index(i)
        for place in ('home', 'food', 'park', 'work'):
            key = (c['id'], place)
            areas = food_areas if place == 'food' else AREAS[place]
            if place == 'work' and c.get('role') == 'Market vendor':
                areas = food_areas  # Vendors work their market stalls.
            spots = []
            if place == 'park':
                spots.append(_group_spot(rank, taken) or _sample(key+(0,), areas, taken, _facing(place)))
            else:
                spots.append(_sample(key+(0,), areas, taken, _facing('food' if areas is food_areas else place)))
            if (i, place) in seat_owner:
                spots.append(deepcopy(seat_owner[(i, place)]))
            elif place == 'park':
                spots.append(_group_spot(rank+17, taken) or _sample(key+(1,), areas, taken, _facing(place)))
            else:
                spots.append(_sample(key+(1,), areas, taken, _facing('food' if areas is food_areas else place)))
            if not extended_market:
                spots.append(_sample(key+(2,), areas, taken, _facing('food' if areas is food_areas else place)))
            places[place]['spots'] = spots
            places[place]['position'] = list(spots[0]['position'])
        for patrol in ('patrol_a', 'patrol_b', 'patrol_c'):
            if patrol not in places:
                continue
            x, _, z = places[patrol]['position']
            face_yaw = 0.0 if z > 0 else round(math.pi, 4)
            primary = {'position': [x, GROUND, z], 'pose': 'stand', 'yaw': face_yaw}
            places[patrol]['spots'] = [primary]
    companion = people[1]['known_places']
    for c in people:
        if c.get('kind') != 'exceptional':
            continue
        if c['id'] in preserve_ids:continue
        index = c['appearance']
        regions = EXCEPTIONAL_REGIONS[index]
        for place in ('home', 'food', 'park', 'work'):
            if regions is None:
                # Near, never on top of, the companion's own primary spot, clamped to district bounds.
                px, py, z = companion[place]['spots'][0]['position']
                areas = [(max(-60.0, px-3.5), min(60.0, px+3.5), max(-58.0, z-3.5), min(106.0, z+3.5), py)]
            else:
                areas = regions[place]
            spot = _sample((c['id'], place, 'agent'), areas, taken, _facing(place))
            spot['yaw'] = None
            c['known_places'][place]['spots'] = [spot]
            c['known_places'][place]['position'] = list(spot['position'])


def stagger(world, preserve_ids=()):
    """Personal routines: shift start, lunch, leisure and bedtime differ, with minute offsets."""
    for index, c in enumerate(world['citizens']):
        if c['id'] in preserve_ids:continue
        c.setdefault('routine_offset', 0)
        if index == 0 or c.get('kind') in {'exceptional', 'police'}:
            continue  # Alex keeps the reference routine; Police retain shift; Exceptional Agents follow observation cycles.
        r = lambda tag: rand(c['id'], 'routine', tag)
        start = [6, 7, 7, 8, 8, 9, 9, 10][int(r('start')*8)]
        lunch = start+3+int(r('lunch')*2)
        back = lunch+1
        leisure = back+3+int(r('leisure')*2)
        home = min(23, leisure+2+int(r('home')*2))
        c['schedule'] = [{'hour': 0, 'place': 'home'}, {'hour': start, 'place': 'work'}, {'hour': lunch, 'place': 'food'},
                         {'hour': back, 'place': 'work'}, {'hour': leisure, 'place': 'park'}, {'hour': home, 'place': 'home'}]
        c['routine_offset'] = int(r('offset')*50)


def spot_goal(c, place, reason, clock, index=None):
    """New goal for a known place, choosing one of the resident's own spots."""
    known = c['known_places'][place]
    spots = known.get('spots') or []
    goal = {'id': str(uuid.uuid4()), 'place': place, 'reason': reason, 'position': list(known['position']), 'started_at': clock}
    if spots and c.get('kind') != 'exceptional':
        if index is None:
            index = int(rand(c['id'], place, int(clock//1800))*len(spots))
        spot = spots[index % len(spots)]
        goal.update(position=list(spot['position']), pose=spot['pose'], yaw=spot['yaw'])
    return goal


def dwell(c, goal):
    """Simulated seconds to linger at one spot before strolling to another within the venue."""
    base = 150+330*rand(c['id'], goal['id'], 'dwell')
    if goal.get('pose') == 'sit':
        base *= 1.8
    if goal['place'] == 'home':
        base *= 3
    return base


def stroll(c, clock):
    """Move between one's own spots at the current venue. Returns True if a new goal was set."""
    g = c['goal']
    if g['reason'] != 'schedule' or c['navigation'] != 'ARRIVED' or c['activity'] == 'travelling' or c.get('kind') == 'exceptional':
        return False
    spots = c['known_places'].get(g['place'], {}).get('spots') or []
    if len(spots) < 2 or g.get('arrived_at') is None or clock-g['arrived_at'] < dwell(c, g):
        return False
    current = next((i for i, s in enumerate(spots) if s['position'] == g['position']), -1)
    choices = [i for i in range(len(spots)) if i != current]
    nxt = choices[int(rand(c['id'], g['id'], 'next')*len(choices))]
    c['goal'] = spot_goal(c, g['place'], 'schedule', clock, nxt)
    c['navigation'] = 'TRAVELLING'  # Activity is retained: a few steps within the venue, not a new trip.
    return True


def retarget(world):
    """After dispersal, point current known-place goals at a valid spot without teleporting anyone."""
    clock = world['clock_seconds']
    for c in world['citizens']:
        g = c['goal']
        if g['place'] not in c['known_places']:
            continue  # assistance/contact meetings keep their observed offsets.
        old = g['id']
        new = spot_goal(c, g['place'], g['reason'], clock, 0)
        c['goal'] = new
        c['navigation'] = 'TRAVELLING'
        action = (c.get('exceptional') or {}).get('action')
        if action and action['goal_id'] == old:
            action['goal_id'] = new['id']
            action['elapsed'] = 0.


def migrate(world, fresh=False):
    """Life version 1 (SQL schema 7): disperse places and stagger routines. Positions are never edited
    for an existing world (Godot owns physical motion); a brand-new world spawns people on their spots."""
    disperse(world)
    stagger(world)
    if fresh:
        for index, c in enumerate(world['citizens']):
            spawn = 'home' if c.get('kind') == 'exceptional' else ['home', 'food', 'park'][index % 3]
            c['position'] = list(c['known_places'][spawn]['position'])
    if fresh:
        retarget(world)
    else:
        # Preserve in-flight goal IDs/coordinates, claims and directed travel so
        # journaled commands retain their valid context after the upgrade.
        for c in world['citizens']:
            g=c['goal']
            if g['place'] in c['known_places']:
                place=c['known_places'][g['place']]
                if g['position'] not in allowed_positions(place):
                    place['spots'].append({'position':list(g['position']), 'pose':g.get('pose','stand'), 'yaw':g.get('yaw')})
    world['life_version'] = LIFE_VERSION


def validate_place(place, kind_exceptional=False):
    spots = place.get('spots')
    if set(place) - {'name', 'position', 'spots'}:
        raise ValueError('Invalid place fields.')
    if spots is None:
        return
    if not isinstance(spots, list) or not 1 <= len(spots) <= MAX_SPOTS:
        raise ValueError('Invalid venue spots.')
    for spot in spots:
        if not isinstance(spot, dict) or set(spot) != {'position', 'pose', 'yaw'} or spot['pose'] not in {'stand', 'sit'}:
            raise ValueError('Invalid venue spot.')
        yaw = spot['yaw']
        if yaw is not None and (isinstance(yaw, bool) or not isinstance(yaw, (int, float)) or not math.isfinite(yaw) or abs(yaw) > 7):
            raise ValueError('Invalid spot heading.')


def allowed_positions(place):
    return [place['position']]+[s['position'] for s in place.get('spots') or []]
