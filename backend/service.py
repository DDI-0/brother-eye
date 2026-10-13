"""App-owned WebSocket service. No offline advancement and no background daemon."""
from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import secrets
import signal
import sys
import time
import uuid

# Works when Godot launches this absolute script from any working directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from backend.citizens import POPULATION_SIZE, advance_citizens, progress
from backend import agent_behavior
from backend.evaluation import evaluate
from backend.history import query as query_history
from backend.interventions import apply as intervene, reject as reject_intervention
from backend.store import PROTOCOL_VERSION, Store, WorldInUse, validate_explorer
from backend.retention import RetiredCommand

LOG = logging.getLogger("brother_eye")


def envelope(kind: str, payload: dict, request_id: str = "") -> dict:
    return {"v": PROTOCOL_VERSION, "type": kind, "id": request_id, "payload": payload}


def write_ready(path: Path, value: dict) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.parent.mkdir(parents=True, exist_ok=True)
    with temporary.open("w") as stream:
        json.dump(value, stream, allow_nan=False)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def owner_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


class Service:
    def __init__(self, store: Store, token: str, owner_pid: int):
        self.store, self.token, self.owner_pid = store, token, owner_pid
        self.session_id = str(uuid.uuid4())
        self.stop = asyncio.Event()
        self.peer = None
        self.last_seen = 0.0
        self.started = time.monotonic()
        self.last_activity = self.started
        self.last_checkpoint = self.started
        self.reason = "shutdown"

    def request_stop(self, reason: str) -> None:
        self.reason = reason
        self.stop.set()

    async def send(self, peer, message: dict) -> None:
        # Derived observations travel with the exact snapshot, outside durable world/receipts.
        state = message.get('payload', {}).get('state', {})
        if state.get('world_id'):
            message = {**message, 'payload': {**message['payload'], 'assessment': evaluate(state)}}
        await peer.send(json.dumps(message, allow_nan=False))

    async def handle(self, peer) -> None:
        from websockets.exceptions import ConnectionClosed
        try:
            hello = decode(await asyncio.wait_for(peer.recv(), timeout=5))
            payload = hello["payload"]
            if hello["type"] != "hello" or not secrets.compare_digest(str(payload.get("token", "")), self.token):
                await peer.close(1008, "Invalid local session")
                return
            if self.peer is not None:
                await peer.close(1013, "An application client is already connected")
                return
            self.peer = peer
            self.last_seen = self.last_activity = time.monotonic()
            self.store.commit("client_connected", {"session_id": self.session_id})
            await self.send(peer, envelope("welcome", {"state": self.store.snapshot(), "session_id": self.session_id, "resumed": self.store.resumed}, hello["id"]))
            LOG.info("Client connected; world=%s", self.store.world["world_id"])
            async for raw in peer:
                message = {}
                try:
                    message = decode(raw)
                    self.last_seen = self.last_activity = time.monotonic()
                    if message["type"] == "heartbeat":
                        continue
                    response = self.command(message)
                    await self.send(peer, response)
                    if message["type"] == "shutdown" and response["type"] == "ack" and not self.last_was_replay:
                        self.request_stop("application_closed")
                        break
                except RetiredCommand as error:
                    await self.send(peer,envelope('error',{'code':'receipt_retired','message':str(error),'state':self.store.snapshot()},message.get('id','')))
                except (ValueError, KeyError, TypeError) as error:
                    # Bad requests never mutate authoritative state or stop the service.
                    request_id = message.get("id", "")
                    await self.send(peer, envelope("error", {"message": str(error)}, request_id))
        except (ConnectionClosed, asyncio.TimeoutError):
            pass
        except (ValueError, KeyError, TypeError) as error:
            await peer.close(1008, str(error)[:100])
        finally:
            if self.peer is peer:
                self.peer = None
                self.last_activity = time.monotonic()
                self.store.commit("client_disconnected", {})
                LOG.info("Client disconnected; clock frozen")

    def command(self, message: dict) -> dict:
        self.last_was_replay=False
        kind, command_id, payload = message["type"], message["id"], message["payload"]
        uuid.UUID(command_id)
        if kind == "query_interventions":
            return envelope("intervention_history", query_history(self.store, payload), command_id)
        if kind not in {"set_clock", "set_explorer", "save", "shutdown", "set_citizen_progress", "set_population_progress", "intervene"}:
            raise ValueError("Unsupported command.")
        previous = self.store.receipt(command_id, message)
        if previous is not None:
            self.last_was_replay=True
            return previous
        before = self.store.snapshot()
        if kind == "set_clock":
            if type(payload.get("paused")) is not bool or payload.get("time_scale") not in (1,10,60) or isinstance(payload.get("time_scale"), bool):
                raise ValueError("Clock needs paused=true/false and time_scale=1, 10 or 60.")
            changes = {"paused": payload["paused"], "time_scale": float(payload["time_scale"])}
        elif kind == "set_explorer":
            changes = {"explorer": validate_explorer(payload)}
        elif kind == "shutdown" and "explorer" in payload:
            changes = {"explorer": validate_explorer(payload["explorer"])}
        else:
            changes = {}
        working = json.loads(json.dumps(before))
        result = None
        if kind == "intervene":
            try:
                result = intervene(working, payload, command_id)
            except (ValueError, TypeError, KeyError) as error:
                working = json.loads(json.dumps(before))
                result = reject_intervention(working, payload, command_id, str(error))
            changes = {"citizens": working["citizens"], "intervention_history": working["intervention_history"]}
        if kind in {"set_citizen_progress", "set_population_progress"}:
            # Validate and apply to a detached state before changing the live world.
            changes = {"citizens": working["citizens"], "intervention_history": working["intervention_history"]}
            reports = payload.get("citizens") if kind == "set_population_progress" else [payload]
            if not isinstance(reports, list) or not 1 <= len(reports) <= len(self.store.world["citizens"]):
                raise ValueError(f"Expected 1–{len(self.store.world['citizens'])} movement reports.")
            if len({r.get('citizen_id') for r in reports if isinstance(r,dict)}) != len(reports):
                raise ValueError("Duplicate or invalid movement report.")
            for report in reports:
                progress(working, report)
            changes["intervention_history"] = working["intervention_history"]
        if kind in {"intervene", "set_citizen_progress", "set_population_progress"}:
            # Movement reports may confirm arrival, but cannot contribute dwell time.
            if kind != "intervene":agent_behavior.advance(working, 0)
            changes.update({key:working[key] for key in ("citizens","assistance_requests","agent_history")})
        if 'serial' in message:changes['command_serial']=message['serial']
        self.store.world.update(changes)
        self.store.world["revision"] += 1
        response = envelope("ack", {"command": kind, "state": {}}, command_id)
        if result is not None:
            response["payload"]["intervention"] = result
        previous_events = {event["id"] for event in before["intervention_history"]}
        audit = [event for event in self.store.world["intervention_history"] if event["id"] not in previous_events]
        try:
            self.store.commit(kind, {"revision": self.store.world["revision"], "interventions": audit, "agent_events": self.agent_events(before)}, (command_id, message, response))
        except BaseException:
            self.store.world = before
            raise
        self.last_checkpoint = time.monotonic()
        return response

    def agent_events(self, before):
        old = {e['id'] for e in before['agent_history']}
        return [e for e in self.store.world['agent_history'] if e['id'] not in old]

    def advance(self, seconds):
        """One clock transaction; significant autonomous consequences are durable immediately."""
        if self.store.world['paused'] or seconds <= 0:return
        before = self.store.snapshot()
        working = json.loads(json.dumps(before))
        working['clock_seconds'] += seconds
        working['tick'] += 1
        advance_citizens(working, seconds)
        agent_behavior.advance(working, seconds)
        self.store.world = working
        events = self.agent_events(before)
        if events:
            working['revision'] += 1
            try:
                self.store.commit('agent_activity', {'agent_events':events, 'revision':working['revision']})
            except BaseException:
                self.store.world = before
                raise
            self.last_checkpoint = time.monotonic()

    async def clock(self) -> None:
        from websockets.exceptions import ConnectionClosed
        previous = time.monotonic()
        broadcast = previous
        while not self.stop.is_set():
            await asyncio.sleep(0.05)
            now = time.monotonic()
            delta, previous = now - previous, now
            if not owner_alive(self.owner_pid):
                self.request_stop("owner_exited")
                break
            live = self.peer is not None and now - self.last_seen < 3.0
            if live and not self.store.world["paused"] and delta < 0.5:
                self.advance(delta * self.store.world["time_scale"])
            if now - self.last_activity > 12:
                self.request_stop("client_timeout")
                break
            if now - self.last_checkpoint >= 2:
                self.store.commit("checkpoint", {"tick": self.store.world["tick"]})
                self.last_checkpoint = now
            if self.peer is not None and now - broadcast >= 0.25:
                broadcast = now
                try:
                    await self.send(self.peer, envelope("snapshot", {"state": self.store.snapshot()}))
                except ConnectionClosed:
                    pass


def decode(raw) -> dict:
    if not isinstance(raw, str):
        raise ValueError("Text JSON messages are required.")
    message = json.loads(raw, parse_constant=lambda value: (_ for _ in ()).throw(ValueError("Non-finite JSON number.")))
    if not isinstance(message, dict) or message.get("v") != PROTOCOL_VERSION or type(message.get("v")) is not int:
        raise ValueError("Unsupported protocol version.")
    if not isinstance(message.get("type"), str) or not isinstance(message.get("id"), str) or not isinstance(message.get("payload"), dict):
        raise ValueError("Invalid message envelope.")
    return message


async def run(args) -> None:
    from websockets.asyncio.server import serve
    store = Store(args.db, tier=args.population_tier)
    service = Service(store, args.token, args.owner_pid)
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, service.request_stop, "signal")
    try:
        async with serve(service.handle, "127.0.0.1", 0, origins=[None], max_size=65536, compression=None, ping_interval=5, ping_timeout=5, close_timeout=1) as server:
            port = server.sockets[0].getsockname()[1]
            write_ready(args.ready, {"pid": os.getpid(), "port": port, "v": PROTOCOL_VERSION})
            LOG.info("Service started pid=%d port=%d resumed=%s", os.getpid(), port, store.resumed)
            task = asyncio.create_task(service.clock())
            # A persistence error must stop the service, not leave a dead clock running.
            waiter = asyncio.create_task(service.stop.wait())
            done, _ = await asyncio.wait((task, waiter), return_when=asyncio.FIRST_COMPLETED)
            if task in done:
                await task
            waiter.cancel()
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task
            store.commit("service_stopped", {"reason": service.reason})
    finally:
        LOG.info("Service stopped: %s", service.reason)
        store.close()
        args.ready.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--ready", type=Path, required=True)
    parser.add_argument("--owner-pid", type=int, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--population-tier", type=int, choices=(0,1,2), default=0)
    args = parser.parse_args()
    if args.owner_pid <= 0 or len(args.token) < 32:
        parser.error("A live owner and a random session token are required.")
    args.db.parent.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(args.db.parent / "service.log", maxBytes=1_000_000, backupCount=3)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    LOG.addHandler(handler)
    LOG.setLevel(logging.INFO)
    try:
        asyncio.run(run(args))
        return 0
    except Exception as error:
        LOG.exception("Service failed")
        message = str(error) if isinstance(error, (WorldInUse, RuntimeError)) else "The city service could not load or save. See service.log; your existing save is preserved."
        write_ready(args.ready, {"pid": os.getpid(), "error": message})
        print("CITY_SERVICE_ERROR", message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
