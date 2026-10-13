"""Stage 5E regression bundle; child harnesses use disposable worlds."""
from pathlib import Path
import argparse
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--evidence-dir',default='docs/previews/stage5e');args=parser.parse_args()
out=ROOT/args.evidence_dir;out.mkdir(parents=True,exist_ok=True)
checks=[('foundation',['tools/check_stage5b.py']),('arbiter',['tools/check_stage5c.py','--evidence-dir',str(out/'arbiter')]),('policies',['tools/check_stage5d.py']),('control',['tools/check_stage4e.py','--evidence-dir',str(out/'control')]),('population',['tools/check_stage3e.py']),('lifecycle',['tools/check_stage2.py'])]
for name,args in checks:
    result=subprocess.run([sys.executable,*args],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=360)
    (out/(name+'.log')).write_text(result.stdout)
    print(name+': '+str(result.returncode),flush=True)
    if result.returncode or 'FAIL ' in result.stdout or 'ERROR:' in result.stdout:
        print(result.stdout,flush=True);raise SystemExit(1)
print('PASS all Stage 5E regression harnesses')
