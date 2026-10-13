"""Stage 6A tests: organic city life, dispersal, seating, and decoupled Exceptional Agents."""
import math
import os
from pathlib import Path
import tempfile
import unittest

from backend.city_life import (
    disperse, stagger, spot_goal, stroll, dwell,
    OBSERVATION_CYCLES, OBSERVATION_RATES,
    SEAT_BENCH, SEAT_X, SPACING
)
from backend.citizens import plan, validate_citizens
from backend.service import Service
from backend.store import Store, validate_world


class CityLifeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "world.sqlite3"
        self.store = Store(self.path)
        self.service = Service(self.store, "a" * 64, os.getpid())

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    @property
    def w(self):
        return self.store.world

    def test_dispersed_unique_spots_no_grid_lines(self):
        """Every resident has distinct venue spots with adequate physical spacing."""
        people = self.w["citizens"]
        validate_world(self.w)
        self.assertEqual(len(people), 34)

        # Check that primary spawn/initial positions are strictly distinct
        spawn_positions = [tuple(c["position"]) for c in people]
        self.assertEqual(len(set(spawn_positions)), 34, "All initial positions must be unique")

        # Check spot spacing within each venue category
        for venue in ("home", "food", "park", "work"):
            primary_positions = [c["known_places"][venue]["position"] for c in people]
            for i in range(len(primary_positions)):
                for j in range(i + 1, len(primary_positions)):
                    p1, p2 = primary_positions[i], primary_positions[j]
                    if abs(p1[1] - p2[1]) < 2.0:
                        dist = math.hypot(p1[0] - p2[0], p1[2] - p2[2])
                        self.assertGreaterEqual(
                            dist, SPACING - 0.05,
                            f"Positions {p1} and {p2} at {venue} violate clearance spacing ({dist:.3f}m)"
                        )

    def test_exceptional_agents_decoupled_routes_and_quarters(self):
        """The four Exceptional Agents have distinct observation routes, quarters, and dwell rates."""
        agents = [c for c in self.w["citizens"] if c.get("kind") == "exceptional"]
        self.assertEqual(len(agents), 4)

        # Profiles have distinct observation cycles
        cycles = [OBSERVATION_CYCLES[c["exceptional"]["profile"]] for c in agents]
        self.assertEqual(len(set(cycles)), 4, "Each agent must follow a distinct observation route cycle")

        # Distinct dwell rates
        rates = [OBSERVATION_RATES[c["exceptional"]["profile"]] for c in agents]
        self.assertEqual(len(set(rates)), 4, "Each agent must have a distinct observation dwell rate")

        # Non-overlapping initial positions and homes
        home_coords = [tuple(c["known_places"]["home"]["position"]) for c in agents]
        self.assertEqual(len(set(home_coords)), 4, "Each Exceptional Agent must have distinct quarters")
        for i in range(len(agents)):
            for j in range(i + 1, len(agents)):
                p1, p2 = home_coords[i], home_coords[j]
                dist = math.hypot(p1[0] - p2[0], p1[2] - p2[2])
                self.assertGreater(dist, 3.0, "Exceptional agent homes must not cluster together")

    def test_bench_seating_and_posture(self):
        """Bench seats exist at plaza, market, and promenade with sit pose and outward orientation."""
        people = self.w["citizens"]
        seated_spots = []
        for c in people:
            for place in c["known_places"].values():
                for spot in place.get("spots", []):
                    if spot.get("pose") == "sit":
                        seated_spots.append(spot)

        self.assertGreaterEqual(len(seated_spots), 12, "Must have bench seating spots allocated")
        for spot in seated_spots:
            x, y, z = spot["position"]
            self.assertTrue(abs(abs(x) - SEAT_X) < 0.5, f"Bench X must align with street benches: {x}")
            self.assertIsNotNone(spot.get("yaw"))
            # Bench seats face outward perpendicular to the bench back
            self.assertTrue(abs(abs(spot["yaw"]) - round(math.pi / 2, 4)) < 0.1)

    def test_staggered_civilian_schedules(self):
        """Civilians have diverse shift start times and minute offsets rather than a monolithic commute."""
        civilians = [c for c in self.w["citizens"] if c.get("kind") == "civilian"]
        shift_starts = [c["schedule"][1]["hour"] for c in civilians]
        self.assertGreaterEqual(len(set(shift_starts)), 3, "Civilians must have staggered shift start hours")

        offsets = [c.get("routine_offset", 0) for c in civilians]
        self.assertGreater(len(set(offsets)), 5, "Civilians must have diverse minute routine offsets")

    def test_in_venue_stroll_and_dwell(self):
        """Residents stroll between their venue spots after lingering, instead of freezing."""
        c = self.w["citizens"][2]  # civilian
        home_spots = c["known_places"]["home"]["spots"]
        self.assertGreater(len(home_spots), 1)

        c["goal"] = spot_goal(c, "home", "schedule", 100.0, index=0)
        c["navigation"] = "ARRIVED"
        c["activity"] = "resting"
        c["goal"]["arrived_at"] = 100.0

        # Before dwell expires, stroll returns False
        self.assertFalse(stroll(c, 105.0))
        self.assertEqual(c["goal"]["position"], home_spots[0]["position"])

        # After dwell expires, stroll picks another spot at the same venue
        dwelling = dwell(c, c["goal"])
        strolled = stroll(c, 100.0 + dwelling + 10.0)
        self.assertTrue(strolled)
        self.assertIn(c["goal"]["position"], [s["position"] for s in home_spots])
        self.assertEqual(c["goal"]["place"], "home")
        self.assertEqual(c["navigation"], "TRAVELLING")


if __name__ == "__main__":
    unittest.main()
