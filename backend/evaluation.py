"""Versioned, deterministic Neon Providence assessments. Reads a snapshot; never acts."""
from collections import Counter

VERSION = 1
RULES = (
    ('hunger', 'high_hunger', 'High hunger', 70, 90, 'food', 'eating', '>'),
    ('energy', 'low_energy', 'Low energy', 20, 10, 'home', 'resting', '<'),
    ('social', 'high_social_need', 'High social need', 75, 95, 'park', 'socializing', '>'),
)
PRIORITY = {'urgent': 0, 'attention': 1, 'notice': 2}


def evaluate(world: dict) -> dict:
    """Evaluate only recorded facts; context identifies the exact source snapshot."""
    people = world.get('citizens', [])
    findings = []
    activities = Counter()
    totals = Counter()
    complete = bool(people)
    for c in people:
        if not all(k in c for k in ('id', 'name', 'needs', 'goal', 'activity', 'navigation', 'known_places')):
            complete = False
            continue
        activities[c['activity']] += 1
        for key, code, title, threshold, urgent, place, activity, comparison in RULES:
            value = c['needs'][key]
            totals[key] += value
            triggered = value > threshold if comparison == '>' else value < threshold
            if not triggered:
                continue
            recovering = c['activity'] == activity and c['navigation'] == 'ARRIVED' and c['goal']['place'] == place
            responding = c['goal']['place'] == place and c['activity'] == 'travelling'
            level = 'urgent' if (value >= urgent if comparison == '>' else value <= urgent) else 'attention'
            response = 'recovering' if recovering else ('travelling_to_recovery' if responding else 'not_addressed')
            context = ('Recovery is active at the recorded destination.' if recovering else
                       'The resident is travelling to their known recovery destination.' if responding else
                       'The current activity does not address this need.')
            recommendation = ('Allow recovery and monitor the need.' if recovering else
                              'Monitor arrival and route status.' if responding else
                              'Review the resident\'s current goal and known recovery destination.')
            findings.append({'id': c['id']+':'+code, 'citizen_id': c['id'], 'name': c['name'],
                             'code': code, 'title': title, 'priority': level, 'response': response,
                             'evidence': {'field': 'needs.'+key, 'value': value, 'comparison': comparison, 'threshold': threshold,
                                          'urgent_threshold': urgent, 'urgent_comparison': '>=' if comparison == '>' else '<=',
                                          'activity': c['activity'], 'navigation': c['navigation'], 'goal_place': c['goal']['place']},
                             'explanation': f'{key.capitalize()} is {value:.1f}%; attention is {comparison} {threshold}%, urgent is {"≥" if comparison == ">" else "≤"} {urgent}%. '+context,
                             'recommendation': recommendation})
        if c['navigation'] in ('WAITING FOR ROUTE', 'WAITING FOR SPACE'):
            route = c['navigation'] == 'WAITING FOR ROUTE'
            findings.append({'id': c['id']+(':route_wait' if route else ':space_wait'), 'citizen_id': c['id'],
                             'name': c['name'], 'code': 'route_wait' if route else 'space_wait',
                             'title': 'Reported route wait' if route else 'Temporary crowd wait',
                             'priority': 'attention' if route else 'notice', 'response': 'waiting',
                             'evidence': {'field': 'navigation', 'value': c['navigation'], 'goal_place': c['goal']['place']},
                             'explanation': ('The character reports waiting for a usable route. This snapshot does not establish how long the wait has lasted.' if route else
                                             'The character reports yielding for space near another pedestrian. This is a local crowd wait, not evidence of a static route obstruction.'),
                             'recommendation': 'Inspect the route and follow the resident.' if route else 'Observe whether the crowd clears before taking further action.'})
    findings.sort(key=lambda f: (PRIORITY[f['priority']], f['citizen_id'], f['code']))
    affected = {f['citizen_id'] for f in findings}
    return {'v': VERSION, 'engine': 'deterministic_rules', 'ruleset': 'civic-needs-navigation-v1',
            'source': {k: world.get(k) for k in ('world_id', 'revision', 'tick', 'clock_seconds', 'paused')},
            'coverage': 'complete' if complete else 'unavailable_or_incomplete',
            'summary': {'population': len(people), 'residents_flagged': len(affected),
                        'priorities': {p: sum(f['priority'] == p for f in findings) for p in PRIORITY},
                        'activities': dict(sorted(activities.items())),
                        'mean_needs': {k: totals[k]/len(people) for k in ('hunger', 'energy', 'social')} if complete else {}},
            'findings': findings}
