"""Stage 6B tier 1 population expansion unit tests."""
import copy
import json
import math
from pathlib import Path
import tempfile
import unittest
import uuid

from backend.citizens import (
    POPULATION_SIZE,
    TIER1_POPULATION_SIZE,
    TIER1_NAMES,
    expand_tier1,
    validate_citizens,
    plan,
    advance_citizens,
    progress,
)
from backend.store import Store, new_world, validate_world


class Tier1Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "world.sqlite3"

    def tearDown(self):
        self.temp.cleanup()

    def test_tier1_expansion_structure(self):
        world = new_world(tier=0)
        self.assertEqual(len(world["citizens"]), POPULATION_SIZE)
        self.assertEqual(world.get("population_tier", 0), 0)

        expand_tier1(world)
        validate_world(world)
        people = world["citizens"]
        self.assertEqual(len(people), TIER1_POPULATION_SIZE)
        self.assertEqual(world.get("population_tier"), 1)

        # Check demographic distribution
        civilians = [c for c in people if c.get("kind") == "civilian"]
        police = [c for c in people if c.get("kind") == "police"]
        exceptional = [c for c in people if c.get("kind") == "exceptional"]
        self.assertEqual(len(civilians), 41)
        self.assertEqual(len(police), 5)
        self.assertEqual(len(exceptional), 4)

        # Uniqueness of identities and names
        ids = {c["id"] for c in people}
        names = {c["name"] for c in people}
        self.assertEqual(len(ids), 50)
        self.assertEqual(len(names), 50)

        # Verify all 16 Tier 1 names are present
        for t1_name in TIER1_NAMES:
            self.assertIn(t1_name, names)

        # Cannot double-expand
        with self.assertRaises(ValueError):
            expand_tier1(world)

    def test_tier1_store_persistence_and_restore(self):
        store = Store(self.path, tier=1)
        self.assertEqual(len(store.world["citizens"]), TIER1_POPULATION_SIZE)
        store.commit("tier1_checkpoint", {"count": 50})
        saved_snapshot = store.snapshot()
        store.close()

        # Reopen and verify complete durable restoration
        store2 = Store(self.path)
        self.assertEqual(len(store2.world["citizens"]), TIER1_POPULATION_SIZE)
        self.assertEqual(store2.world["citizens"], saved_snapshot["citizens"])
        self.assertEqual(store2.world["revision"], saved_snapshot["revision"])
        self.assertEqual(store2.db.execute("PRAGMA quick_check").fetchone()[0], "ok")
        store2.close()

    def test_tier1_dispersal_and_spacing(self):
        world = new_world(tier=1)
        people = world["citizens"]
        positions = [tuple(c["position"]) for c in people]
        self.assertEqual(len(positions), 50)
        self.assertEqual(len(set(positions)), 50, "All 50 residents must spawn at distinct positions")

        # Verify unique initial positions and per-venue spot clearance
        for venue in ("home", "food", "park", "work"):
            primary_positions = [c["known_places"][venue]["position"] for c in people]
            for i in range(len(primary_positions)):
                for j in range(i + 1, len(primary_positions)):
                    p1, p2 = primary_positions[i], primary_positions[j]
                    if abs(p1[1] - p2[1]) < 2.0:
                        dist = math.hypot(p1[0] - p2[0], p1[2] - p2[2])
                        self.assertGreaterEqual(
                            dist,
                            1.30,
                            f"Residents {people[i]['name']} and {people[j]['name']} too close at {venue}: {dist:.3f}m",
                        )

    def test_tier1_progress_reporting_and_advance(self):
        world = new_world(tier=1)
        advance_citizens(world, 10.0)
        for c in world["citizens"]:
            payload = {
                "citizen_id": c["id"],
                "goal_id": c["goal"]["id"],
                "seq": c["motion_seq"] + 1,
                "position": list(c["position"]),
                "yaw": float(c["yaw"]),
                "navigation": "TRAVELLING",
            }
            self.assertTrue(progress(world, payload))
            self.assertEqual(c["motion_seq"], 1)


if __name__ == "__main__":
    unittest.main()
