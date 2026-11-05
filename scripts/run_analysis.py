"""Run versioned models and publish attributable reports, even when a stage fails."""
import argparse
from datetime import datetime,timezone
from pathlib import Path
import shutil
import subprocess
import sys
from common import ROOT, read_json, write_json, provenance, inputs
from preflight import check
from build_dashboard_data import build


def execute(stage, runtime='auto', executable=None):
    directory=ROOT/'results'/stage
    directory.mkdir(parents=True,exist_ok=True)
    output=directory/'summary.json'
    # Retire old output first: a failed new attempt must never expose an old green report.
    output.unlink(missing_ok=True)
    prov={}
    try:
        prov=provenance(ROOT)
        check()
        if stage=='openrocket':
            command=[sys.executable,str(ROOT/'openrocket/run_openrocket.py')]
            label='OpenRocket 24.12 / Java 17'
        else:
            chosen=runtime
            if chosen=='auto': chosen='matlab' if shutil.which('matlab') else 'octave'
            binary=executable or shutil.which('matlab' if chosen=='matlab' else 'octave') or shutil.which('octave-cli')
            if not binary: raise RuntimeError('Install MATLAB or GNU Octave, or specify --executable for the selected runtime')
            expression="addpath('matlab'); run_ci(pwd, false);"
            command=[binary,'-batch',expression] if chosen=='matlab' else [binary,'--no-gui','--quiet','--eval',expression]
            label='MATLAB' if chosen=='matlab' else 'GNU Octave (same MATLAB numerical source; no UI)'
        prov['runtime']=label
        print('Running',stage,'with',label,flush=True)
        with (directory/'run.log').open('w',encoding='utf-8') as log:
            completed=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=1800,check=False)
        if not output.is_file(): raise RuntimeError(f'{stage} produced no report; see results/{stage}/run.log')
        data=read_json(output)
        data['provenance']=prov
        data['status']='complete' if completed.returncode==0 else 'error'
        if inputs()[0]!=prov['input_digest']:
            data['status']='stale';data['error']='Inputs changed during this run; run again.'
        if completed.returncode: data['error']=f'Engine exited with code {completed.returncode}; see run.log'
        write_json(output,data)
        return data['status']=='complete'
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError,KeyError) as exc:
        write_json(output,dict(schema_version=1,status='error',error=str(exc),provenance=prov,
                               cases=[],sections=[],requirements=[],notes=[],simulation_error_count=1))
        print(f'{stage}: {exc}',file=sys.stderr)
        return False


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model',choices=['all','matlab','openrocket'],default='all')
    parser.add_argument('--runtime',choices=['auto','matlab','octave'],default='auto')
    parser.add_argument('--executable',help='Path to the selected MATLAB/Octave executable')
    args=parser.parse_args()
    stages=['matlab','openrocket'] if args.model=='all' else [args.model]
    passed=True
    for stage in stages: passed=execute(stage,args.runtime,args.executable) and passed
    write_json(ROOT/'results/dashboard.json',build())
    return 0 if passed else 1

if __name__=='__main__': sys.exit(main())
