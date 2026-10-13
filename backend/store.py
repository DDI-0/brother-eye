"""Versioned, atomic SQLite checkpoints and durable command receipts."""
from __future__ import annotations

import fcntl
import json
import math
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

from backend.citizens import seed_citizens, expand_population, validate_citizens

SCHEMA_VERSION = 8
PROTOCOL_VERSION = 1


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_world(tier: int = 0) -> dict:
    if type(tier) is not int or tier not in (0,1,2):
        raise ValueError('Supported population tiers are 0 (34), 1 (50) and 2 (100).')
    world = {
        "world_id": str(uuid.uuid4()), "seed": 71026, "clock_seconds": 0.0,
        "tick": 0, "revision": 0, "paused": False, "time_scale": 1.0,
        "created_at": utc_now(), "saved_at": None, "explorer": None,
        "command_serial": 0,
    }
    seed_citizens(world)
    expand_population(world)
    from backend.interventions import migrate
    migrate(world)
    from backend.exceptional import migrate as migrate_exceptional
    migrate_exceptional(world)
    from backend.agent_behavior import migrate as migrate_behavior
    migrate_behavior(world)
    from backend.agent_policies import migrate as migrate_policies
    migrate_policies(world)
    from backend.city_life import migrate as migrate_city_life
    migrate_city_life(world, fresh=True)
    if tier >= 1:
        from backend.citizens import expand_tier1
        expand_tier1(world)
    if tier >= 2:
        from backend.citizens import expand_tier2
        expand_tier2(world)
    return world


class WorldInUse(RuntimeError):
    pass


class Store:
    def __init__(self, path: Path, tier: int = 0):
        if type(tier) is not int or tier not in (0, 1, 2):
            raise ValueError('Supported population tiers are 0 (34), 1 (50) and 2 (100).')
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = self.path.with_suffix(self.path.suffix + ".lock").open("a+")
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise WorldInUse("This city is already open in another application window.") from None
        try:
            self.db = sqlite3.connect(self.path, timeout=3)
            version = self.db.execute("PRAGMA user_version").fetchone()[0]
            if version > SCHEMA_VERSION:
                raise RuntimeError("The save was created by a newer version. It has not been changed.")
            self.db.execute("PRAGMA journal_mode=WAL")
            self.db.execute("PRAGMA synchronous=FULL")
            self.db.execute("PRAGMA journal_size_limit=4194304")
            self.db.execute("PRAGMA wal_autocheckpoint=256")
            if version == 0:
                with self.db:
                    self.db.execute("BEGIN IMMEDIATE")
                    self.db.execute("CREATE TABLE world (singleton INTEGER PRIMARY KEY CHECK(singleton=1), state_json TEXT NOT NULL)")
                    self.db.execute("CREATE TABLE events (seq INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL, kind TEXT NOT NULL, data_json TEXT NOT NULL)")
                    self.db.execute("CREATE TABLE receipts (command_id TEXT PRIMARY KEY, request_json TEXT NOT NULL, response_json TEXT NOT NULL)")
                    self.db.execute("PRAGMA user_version=1")
            check = self.db.execute("PRAGMA quick_check").fetchone()[0]
            if check != "ok":
                raise RuntimeError("SQLite integrity check failed. The existing save is preserved.")
            row = self.db.execute("SELECT state_json FROM world WHERE singleton=1").fetchone()
            self.resumed = row is not None
            self.world = json.loads(row[0]) if row else new_world(tier=tier)
            if version < 2 and row:
                seed_citizens(self.world)
            if version < 3 and row:
                expand_population(self.world)
            if version < 4:
                from backend.interventions import migrate
                migrate(self.world)
            if version < 5 and row:
                from backend.exceptional import migrate as migrate_exceptional
                migrate_exceptional(self.world)
            if version < 6 and row:
                from backend.agent_behavior import migrate as migrate_behavior
                migrate_behavior(self.world)
            if version < 7 and row:
                from backend.agent_policies import migrate as migrate_policies
                migrate_policies(self.world)
                self.world['revision'] += 1
            life_migrated = bool(row and self.world.get('life_version') != 1)
            if life_migrated:
                if self.world.get('life_version', 0) > 1:
                    raise RuntimeError('The city-life version is newer than this application.')
                from backend.city_life import migrate as migrate_city_life
                migrate_city_life(self.world, fresh=False)
                if version >= 7:self.world['revision'] += 1
            expanded = bool(row and len(self.world['citizens']) < (34,50,100)[tier])
            if expanded:
                from backend.citizens import expand_tier1
                if len(self.world['citizens']) == 34:expand_tier1(self.world)
                if tier == 2:
                    from backend.citizens import expand_tier2
                    expand_tier2(self.world)
            if version < 8:
                self.world.setdefault('command_serial',0)
                if row and version>=7 and not life_migrated:self.world['revision']+=1
            validate_world(self.world)
            from backend.retention import setup as setup_retention, prune
            if version < 8 or life_migrated or expanded:
                with self.db:
                    self.db.execute("BEGIN IMMEDIATE")
                    self.db.execute("UPDATE world SET state_json=? WHERE singleton=1", (json.dumps(self.world, allow_nan=False),))
                    self.db.execute("PRAGMA user_version=8")
                    setup_retention(self.db)
                    if row and version < 4:
                        self.db.execute("INSERT INTO events(at,kind,data_json) VALUES(?,?,?)", (utc_now(), "citizens_migrated" if version < 2 else ("population_migrated" if version < 3 else "interventions_migrated"), "{}"))
                    if row and version < 5:
                        self.db.execute("INSERT INTO events(at,kind,data_json) VALUES(?,?,?)", (utc_now(), "exceptional_agents_migrated", json.dumps({"added": 4, "revision": self.world['revision']})))
                    if row and version < 6:
                        self.db.execute("INSERT INTO events(at,kind,data_json) VALUES(?,?,?)", (utc_now(), "arbiter_behavior_migrated", json.dumps({"revision": self.world['revision']})))
                    if row and version < 7:
                        self.db.execute("INSERT INTO events(at,kind,data_json) VALUES(?,?,?)", (utc_now(), "exceptional_policies_migrated", json.dumps({"revision":self.world["revision"]})))
                    for changed, kind in ((life_migrated, 'city_life_migrated'), (expanded, 'population_tier_expanded')):
                        if changed:
                            self.db.execute("INSERT INTO events(at,kind,data_json) VALUES(?,?,?)", (utc_now(), kind, json.dumps({'revision':self.world['revision']})))
                    if row and version<8:
                        self.db.execute("INSERT INTO events(at,kind,data_json) VALUES(?,?,?)",(utc_now(),'retention_migrated','{}'))
                    prune(self.db)
            if not row:
                self.commit("world_created", {"world_id": self.world["world_id"]})
            else:
                with self.db:prune(self.db)
            self.commits_since_prune=0
        except BaseException:
            if hasattr(self, "db"):
                self.db.close()
            self.lock.close()
            raise

    def receipt(self, command_id: str, request: dict) -> dict | None:
        from backend.retention import command_id as serial_id, request_hash, RetiredCommand
        serial=request.get('serial')
        if 'serial' in request and (type(serial) is not int or not 1<=serial<=2**53-1 or command_id!=serial_id(self.world['world_id'],serial)):
            raise ValueError('Invalid command serial or identity.')
        row = self.db.execute("SELECT request_json,response_json FROM receipts WHERE command_id=?", (command_id,)).fetchone()
        if not row:
            legacy=self.db.execute('SELECT request_hash,response_meta FROM legacy_receipts WHERE command_id=?',(command_id,)).fetchone()
            if legacy:
                if request_hash(request)!=legacy[0]:raise ValueError('A command ID cannot be reused for a different request.')
                response=json.loads(legacy[1]);response['payload'].update(state=self.snapshot(),receipt_retired=True)
                return response
            if serial is not None:
                if serial<=self.world['command_serial']:raise RetiredCommand('Historical receipt retired; saved state is authoritative. This request was not executed again.')
                if serial!=self.world['command_serial']+1:raise ValueError('Command serial is out of order; preserve and replay the pending journal.')
            return None
        if request_hash(json.loads(row[0])) != request_hash(request):
            raise ValueError("A command ID cannot be reused for a different request.")
        return json.loads(row[1])

    def commit(self, kind: str, data: dict, command: tuple[str, dict, dict] | None = None) -> None:
        self.world["saved_at"] = utc_now()
        # Receipt state and checkpoint share one transaction; acknowledge only afterward.
        if command:
            command[2]["payload"]["state"] = self.snapshot()
        with self.db:
            self.db.execute("INSERT INTO world VALUES(1,?) ON CONFLICT(singleton) DO UPDATE SET state_json=excluded.state_json", (json.dumps(self.world, allow_nan=False),))
            event_seq=self.db.execute("INSERT INTO events(at,kind,data_json) VALUES(?,?,?)", (utc_now(), kind, json.dumps(data, allow_nan=False))).lastrowid
            if command:
                command_id, request, response = command
                self.db.execute("INSERT INTO receipts(command_id,request_json,response_json,committed_seq) VALUES(?,?,?,?)", (command_id, json.dumps(request, sort_keys=True, allow_nan=False), json.dumps(response, allow_nan=False),event_seq))
            from backend.retention import PRUNE_INTERVAL, prune
            self.commits_since_prune=getattr(self,'commits_since_prune',0)+1
            if self.commits_since_prune>=PRUNE_INTERVAL:
                prune(self.db)
                self.commits_since_prune=0

    def snapshot(self) -> dict:
        # Detached state avoids caller mutations and serializes exactly what the wire uses.
        return json.loads(json.dumps(self.world, allow_nan=False))

    def close(self) -> None:
        self.db.close()
        self.lock.close()


def number(value, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not minimum <= value <= maximum:
        raise ValueError(f"Expected a finite number between {minimum} and {maximum}.")
    return float(value)


def vector(value, limits: tuple[tuple[float, float], ...]) -> list[float]:
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError("Expected a three-component vector.")
    return [number(component, *limit) for component, limit in zip(value, limits)]


def validate_explorer(value) -> dict:
    if not isinstance(value, dict) or type(value.get("observing")) is not bool:
        raise ValueError("Invalid explorer state.")
    return {
        "position": vector(value.get("position"), ((-1e6,1e6),(-100,1e6),(-1e6,1e6))),
        "yaw": number(value.get("yaw"), -1e6, 1e6),
        "ground_pitch": number(value.get("ground_pitch"), -1.5, 1.5),
        "observer_position": vector(value.get("observer_position"), ((-400,400),(2,330),(-420,420))),
        "observer_rotation": vector(value.get("observer_rotation"), ((-1.5,1.5),(-1e6,1e6),(-3.2,3.2))),
        "flight_speed": number(value.get("flight_speed"), 3, 140),
        "observing": value["observing"],
    }


def validate_world(world: dict) -> None:
    uuid.UUID(world["world_id"])
    if world["seed"] != 71026 or type(world["paused"]) is not bool:
        raise ValueError("Invalid world metadata.")
    number(world["clock_seconds"], 0, 1e15)
    number(world["time_scale"], 0.1, 60)
    for key in ("tick", "revision"):
        if type(world[key]) is not int or world[key] < 0:
            raise ValueError("Invalid world counter.")
    if type(world.get('command_serial')) is not int or not 0<=world['command_serial']<=2**53-1:
        raise ValueError('Invalid command sequence watermark.')
    validate_citizens(world["citizens"])
    from backend.exceptional import validate as validate_exceptional
    validate_exceptional(world)
    from backend.agent_behavior import validate as validate_behavior
    validate_behavior(world)
    from backend.interventions import validate
    validate(world)
    if world["explorer"] is not None:
        validate_explorer(world["explorer"])

