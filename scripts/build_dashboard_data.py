"""Join engine reports without turning missing, failed or stale analyses into passes."""
from common import ROOT, read_json, write_json, inputs, cases
from pathlib import Path


def as_list(value):
    if value is None: return []
    return value if isinstance(value,list) else [value]


def build(root=ROOT):
    errors=[]
    vehicle='SLVT'
    try:
        vehicle=read_json(root/'config/vehicle.json')['vehicle_name']
        definitions=cases(root); digest,_=inputs(root)
        requirements=read_json(root/'config/requirements.json')['requirements']
    except (OSError,ValueError,KeyError,TypeError) as exc:
        definitions=[];digest='';requirements=[];errors.append(str(exc))
    names={c['name'] for c in definitions}
    models={}
    for model in ('matlab','openrocket'):
        path=root/'results'/model/'summary.json'
        info=dict(name=model,status='missing',fresh=False,coverage=([r['id'] for r in requirements] if model=='matlab' else ['2.1','2.14','2.20.6']),cases=[],sections=[],requirements=[],notes=[])
        if path.is_file():
            try:
                data=read_json(path)
                info.update(data)
                for key in ('cases','sections','requirements','notes'):
                    info[key]=as_list(data.get(key))
                info['name']=model
                prov=data.get('provenance',{})
                info['fresh']=bool(digest) and prov.get('input_digest')==digest
                returned=[c['case_name'] for c in info['cases']]
                complete=(set(returned)==names and len(returned)==len(names) and bool(names))
                if data.get('status') in ('error','skipped'):
                    info['status']=data['status']
                elif data.get('simulation_error_count',0) or any(c.get('run_status')!='ok' for c in info['cases']):
                    info['status']='error'
                elif not complete: info['status']='incomplete'
                elif not info['fresh']: info['status']='stale'
                else: info['status']='complete'
                info['coverage']=[r['id'] for r in requirements] if model=='matlab' else ['2.1','2.14','2.20.6']
                if model=='matlab' and info['status']=='complete':
                    for case in definitions:
                        count=sum(s.get('case_name')==case['name'] for s in info['sections'])
                        if count != (4 if case['payload_deployment']=='deploy' else 3):
                            info['status']='incomplete'; break
                if info['status']=='complete':
                    for case in definitions:
                        for rid in info['coverage']:
                            checks=[c for c in info['requirements'] if c.get('case_name')==case['name'] and c.get('requirement_id')==rid]
                            expected=(4 if case['payload_deployment']=='deploy' else 3) if model=='matlab' and rid in ('3.2','3.10','3.11') else 1
                            if len(checks)!=expected or any(c.get('status') not in ('pass','fail') for c in checks):
                                info['status']='incomplete'
            except (ValueError,KeyError,TypeError,OSError) as exc:
                info.update(status='error',error=f'Cannot read report: {exc}',fresh=False)
        models[model]=info
    status='complete' if all(m['status']=='complete' for m in models.values()) else 'incomplete'
    return dict(schema_version=1,vehicle=vehicle,
                input_digest=digest,expected_case_count=len(definitions),case_definitions=definitions,
                requirement_definitions=requirements,models=models,status=status,errors=errors)

if __name__=='__main__':
    write_json(ROOT/'results/dashboard.json',build())
