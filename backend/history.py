"""Read-only, cursor-paged projection of committed intervention audit events."""
import math


def integer(value, minimum, maximum):
    if isinstance(value, bool) or not isinstance(value, (int,float)) or not math.isfinite(value) or int(value)!=value or not minimum<=value<=maximum:
        raise ValueError('Invalid history cursor or page size.')
    return int(value)


def query(store, payload):
    if set(payload) != {'citizen_id','before_seq','before_index','limit'}:
        raise ValueError('Invalid history query fields.')
    target = payload['citizen_id']
    if not isinstance(target,str) or len(target)>80:
        raise ValueError('Invalid history target.')
    seq = integer(payload['before_seq'],0,2**53-1)
    index = integer(payload['before_index'],0,1000)
    limit = integer(payload['limit'],1,50)
    rows = store.db.execute('''
        SELECT e.seq, CAST(j.key AS INTEGER), j.value
        FROM events e, json_each(e.data_json, '$.interventions') j
        WHERE (?='' OR json_extract(j.value,'$.citizen_id')=?)
          AND (?=0 OR e.seq<? OR (e.seq=? AND CAST(j.key AS INTEGER)<?))
        ORDER BY e.seq DESC, CAST(j.key AS INTEGER) DESC LIMIT ?
    ''',(target,target,seq,seq,seq,index,limit+1)).fetchall()
    import json
    from backend.retention import status
    items = [{'event_seq':row[0],'event_index':row[1],**json.loads(row[2])} for row in rows[:limit]]
    return {'world_id':store.world['world_id'],'revision':store.world['revision'],
            'citizen_id':target,'entries':items,'has_more':len(rows)>limit,
            'retention':status(store.db),
            'next_cursor': {'before_seq':items[-1]['event_seq'],'before_index':items[-1]['event_index']} if items else None}
