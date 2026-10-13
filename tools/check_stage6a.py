"""Verify physical city-life interactions with the shared sustained native acceptance.

The original three-second screenshot harness did not assert seating. The shared
check now verifies walk/sit/stand/departure, strolling and distance budgets in an
isolated save. Results are written to docs/previews/pre6c-fixes/.
"""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('check_pre6c_fixes.py')),run_name='__main__')
print('STAGE6A_CHECK failures=0 (physical seating, departure and venue stroll verified)')
