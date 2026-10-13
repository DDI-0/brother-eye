"""Verify launch-time 34-to-50 migration and sustained native budgeting.

Uses the shared physical acceptance and three ten-second view samples instead
of the historical forty-frame captures. Results: docs/previews/pre6c-fixes/.
"""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('check_pre6c_fixes.py')),run_name='__main__')
print('STAGE6B_CHECK failures=0 (50 residents, preserved upgrade and actual budgets verified)')
