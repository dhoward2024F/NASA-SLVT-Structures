"""Validate versioned inputs before launching expensive engines."""
from common import ROOT, cases, read_json, within, number
import argparse


def check(root=ROOT):
    matrix = cases(root)
    vehicle = read_json(root/'config/vehicle.json')
    if vehicle['units'] != 'imperial': raise ValueError('Expected imperial vehicle units')
    motor = within(root, vehicle['propulsion']['motor_file'])
    if not motor.is_file(): raise ValueError(f'Missing motor curve: {motor.relative_to(root)}')
    model = read_json(root/'config/matlab_model.json')
    cfg = read_json(root/'config/automation.json')['openrocket']
    if not within(root,cfg['model_file']).is_file(): raise ValueError('Selected OpenRocket model is missing')
    if cfg['coverage'] != 'ascent_only': raise ValueError('OpenRocket adapter supports ascent_only')
    reqs = read_json(root/'config/requirements.json')['requirements']
    expected={'2.1','2.12','2.14','2.20.6','3.2','3.10','3.11'}
    if {r['id'] for r in reqs} != expected or len(reqs)!=7: raise ValueError('Expected the seven configured requirement IDs')
    for r in reqs:
        for key in (('minimum','maximum') if r['type']=='range' else ('value',)):
            number(r[key],f"Requirement {r['id']} {key}")
        if r['type']=='range' and r['minimum']>r['maximum']: raise ValueError('Reversed requirement bounds')
    print(f'Inputs valid: {len(matrix)} cases, {len(reqs)} requirements; motor {motor.name}.')
    if any(v is None for v in vehicle['mass'].values()):
        print('Note: null masses use the explicit MATLAB fallbacks; model values still need team review.')
    return matrix

if __name__=='__main__':
    check()
