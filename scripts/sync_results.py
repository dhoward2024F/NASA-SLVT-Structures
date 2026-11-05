"""Retrieve the latest completed private workflow artifact using your gh login."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import shutil
from common import ROOT,read_json,write_json
from build_dashboard_data import build


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id',type=int,help='Download a specific workflow run instead of the latest completed main run')
    args=parser.parse_args()
    repo=read_json(ROOT/'config/automation.json')['repository']
    if not shutil.which('gh'): raise SystemExit('Install GitHub CLI and run gh auth login first.')
    run=args.run_id
    if run is None:
        import json
        runs=json.loads(subprocess.check_output(['gh','run','list','--repo',repo,'--workflow','mission-analysis.yml',
              '--branch','main','--status','completed','--limit','1','--json','databaseId'],text=True))
        if not runs: raise SystemExit('No completed mission-analysis workflow exists yet.')
        run=runs[0]['databaseId']
    with tempfile.TemporaryDirectory() as temporary:
        subprocess.run(['gh','run','download',str(run),'--repo',repo,'--name','mission-analysis','--dir',temporary],check=True)
        source=Path(temporary)
        for model in ('matlab','openrocket'):
            summary=source/model/'summary.json'
            if not summary.is_file(): raise ValueError(f'Artifact lacks {model}/summary.json; local results were not changed')
            read_json(summary)
        for model in ('matlab','openrocket'):
            dest=ROOT/'results'/model
            if dest.exists(): shutil.rmtree(dest)
            shutil.copytree(source/model,dest)
    write_json(ROOT/'results/dashboard.json',build())
    print(f'Downloaded run {run}. Dashboard checks these results against your local model/config files.')

if __name__=='__main__': main()
