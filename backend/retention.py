"""Bounded hot history and sequenced receipts, preserving legacy retry identities."""
import hashlib
import json
import uuid

RECEIPT_LIMIT=128
RECENT_EVENTS=512
SIGNIFICANT_EVENTS=512
PRUNE_INTERVAL=32

class RetiredCommand(ValueError):
    """Sequence already consumed; detailed response is outside the retained window."""


def command_id(world_id,serial):
    return str(uuid.UUID(bytes=hashlib.sha256(f'{world_id}:{serial}'.encode()).digest()[:16],version=4))


def request_hash(request):
    def normalize(value):
        if isinstance(value,dict):return {k:normalize(v) for k,v in value.items()}
        if isinstance(value,list):return [normalize(v) for v in value]
        if isinstance(value,float) and value.is_integer():return int(value)
        return value
    return hashlib.sha256(json.dumps(normalize(request),sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def setup(db):
    if 'committed_seq' not in {row[1] for row in db.execute('PRAGMA table_info(receipts)')}:
        db.execute('ALTER TABLE receipts ADD COLUMN committed_seq INTEGER')
        db.execute('UPDATE receipts SET committed_seq=rowid')
    db.execute('CREATE INDEX IF NOT EXISTS receipt_order ON receipts(committed_seq)')
    db.execute('CREATE TABLE IF NOT EXISTS legacy_receipts(command_id TEXT PRIMARY KEY, request_hash TEXT NOT NULL, response_meta TEXT NOT NULL)')
    db.execute('CREATE TABLE IF NOT EXISTS retention(singleton INTEGER PRIMARY KEY CHECK(singleton=1), pruned_through INTEGER NOT NULL DEFAULT 0, pruned_events INTEGER NOT NULL DEFAULT 0, pruned_audit INTEGER NOT NULL DEFAULT 0)')
    db.execute('INSERT OR IGNORE INTO retention(singleton) VALUES(1)')


def prune(db):
    """Must run inside the caller's state/receipt transaction; never commits itself."""
    cutoff=db.execute('SELECT committed_seq FROM receipts ORDER BY committed_seq DESC LIMIT 1 OFFSET ?', (RECEIPT_LIMIT-1,)).fetchone()
    compacted=0
    while cutoff:
        # Bound migration memory even for a legacy database containing many
        # large response snapshots; do not fetch every old snapshot at once.
        stale=db.execute('SELECT command_id,request_json,response_json FROM receipts WHERE committed_seq<? ORDER BY committed_seq LIMIT 16',(cutoff[0],)).fetchall()
        if not stale:break
        for identifier,raw_request,raw_response in stale:
            request=json.loads(raw_request)
            if 'serial' not in request:
                response=json.loads(raw_response);response['payload'].pop('state',None);response['payload'].pop('assessment',None)
                db.execute('INSERT INTO legacy_receipts VALUES(?,?,?)',(identifier,request_hash(request),json.dumps(response,allow_nan=False)))
        db.executemany('DELETE FROM receipts WHERE command_id=?',[(row[0],) for row in stale])
        compacted+=len(stale)
    # Keep newest operational events plus an independent budget for meaningful
    # intervention/agent outcomes. Genesis/migration records are finite and pinned.
    rows=db.execute('''SELECT seq,coalesce(json_array_length(data_json,'$.interventions'),0) FROM events WHERE seq NOT IN
      (SELECT seq FROM events ORDER BY seq DESC LIMIT ?)
      AND seq NOT IN (SELECT seq FROM events WHERE
        json_array_length(data_json,'$.interventions')>0 OR json_array_length(data_json,'$.agent_events')>0
        ORDER BY seq DESC LIMIT ?)
      AND kind NOT IN ('world_created','citizens_migrated','population_migrated','interventions_migrated',
       'exceptional_agents_migrated','arbiter_behavior_migrated','exceptional_policies_migrated',
       'city_life_migrated','population_tier_expanded','retention_migrated')''',(RECENT_EVENTS,SIGNIFICANT_EVENTS)).fetchall()
    if rows:
        db.executemany('DELETE FROM events WHERE seq=?',[(r[0],) for r in rows])
        db.execute('UPDATE retention SET pruned_through=max(pruned_through,?),pruned_events=pruned_events+?,pruned_audit=pruned_audit+? WHERE singleton=1',(max(r[0] for r in rows),len(rows),sum(r[1] for r in rows)))
    return {'receipts_compacted':compacted,'events_pruned':len(rows)}


def status(db):
    row=db.execute('SELECT pruned_through,pruned_events,pruned_audit FROM retention WHERE singleton=1').fetchone()
    return {'recent_event_limit':RECENT_EVENTS,'significant_event_limit':SIGNIFICANT_EVENTS,'receipt_limit':RECEIPT_LIMIT,
            'pruned_through_seq':row[0],'pruned_events':row[1],'pruned_audit_entries':row[2]}
