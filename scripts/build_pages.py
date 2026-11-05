"""Package a read-only GitHub Pages dashboard; never publish repository source."""
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil

from common import ROOT, read_json, write_json
from build_dashboard_data import build


def package(root=ROOT):
    config=read_json(root/'config/automation.json')
    enabled=config.get('pages',{}).get('enabled',False)
    if not isinstance(enabled,bool):
        raise ValueError('pages.enabled must be a JSON boolean')
    data=build(root)
    # This allowlist is the entire published surface. Exclude raw inputs,
    # curves, trajectories, logs, absolute paths, and source-file manifests.
    snapshot={key:data[key] for key in ('schema_version','vehicle','expected_case_count',
              'case_definitions','requirement_definitions','status')}
    snapshot['errors']=['Analysis configuration is incomplete; inspect the private workflow logs.'] if data['errors'] else []
    snapshot['models']={}
    for name,model in data['models'].items():
        visible={key:model[key] for key in ('name','status','fresh','coverage','cases','sections','requirements','notes')}
        visible['provenance']={key:model.get('provenance',{}).get(key,'') for key in ('created_at','git_commit','runtime')}
        if model.get('error'):
            visible['error']='Analysis did not complete; inspect the private workflow logs.'
        snapshot['models'][name]=visible
    snapshot['publication']={
        'repository':config['repository'],
        'workflow_run_id':os.environ.get('GITHUB_RUN_ID',''),
        'created_at':datetime.now(timezone.utc).isoformat(),
    }
    target=root/'_site'
    if target.is_symlink():
        raise ValueError('Refusing to package into a symlink')
    if target.exists():
        shutil.rmtree(target)
    target.mkdir()
    for name in ('index.html','app.js','styles.css'):
        source=root/'dashboard'/name
        if source.is_symlink():
            raise ValueError('Dashboard assets must be regular files')
        shutil.copyfile(source,target/name)
    page=target/'index.html'
    html=page.read_text(encoding='utf-8')
    if 'data-hosting="local"' not in html:
        raise ValueError('Dashboard hosting-mode marker is missing')
    page.write_text(html.replace('data-hosting="local"','data-hosting="pages"'),encoding='utf-8')
    write_json(target/'data.json',snapshot)
    (target/'.nojekyll').write_text('',encoding='utf-8')
    return enabled


if __name__=='__main__':
    enabled=package()
    output=os.environ.get('GITHUB_OUTPUT')
    if output:
        with Path(output).open('a',encoding='utf-8') as file:
            file.write(f'enabled={str(enabled).lower()}\n')
    print(f'Packaged _site/; Pages publishing enabled: {enabled}')
