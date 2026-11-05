"""Shared configuration, case expansion and provenance. Python 3.10+."""
from __future__ import annotations
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def read_json(path):
    def reject(value):
        raise ValueError(f'Nonstandard JSON value: {value}')
    return json.loads(Path(path).read_text(encoding='utf-8'), parse_constant=reject)


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    os.replace(temporary, path)


def number(value, label, minimum=None, maximum=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f'{label} must be a finite number')
    if minimum is not None and value < minimum or maximum is not None and value >= maximum:
        raise ValueError(f'{label} is outside the allowed range')
    return value


def within(root, relative):
    path = (Path(root) / relative).resolve()
    if not path.is_relative_to(Path(root).resolve()):
        raise ValueError(f'Path must remain inside the repository: {relative}')
    return path


def cases(root=ROOT):
    data = read_json(root / 'config/analysis_cases.json')
    launch = read_json(root / 'config/launch_conditions.json')
    rows = [dict(c) for c in data['cases']]
    custom = data.get('custom_condition', {})
    enabled = custom.get('enabled', False)
    if not isinstance(enabled, bool):
        raise ValueError('custom_condition.enabled must be true or false')
    if enabled:
        for mode in custom['payload_deployment']:
            for recovery in custom['recovery_configuration']:
                rows.append(dict(name=f"{custom['name']}_{mode}_{recovery}",
                                 wind_speed_mph=custom['wind_speed_mph'],
                                 launch_angle_from_vertical_deg=custom['launch_angle_from_vertical_deg'],
                                 payload_deployment=mode, recovery_configuration=recovery))
    if not 1 <= len(rows) <= 2000:
        raise ValueError('Expected 1–2000 cases')
    for row in rows:
        row.setdefault('wind_speed_mph', launch['environment']['wind_speed_mph'])
        row.setdefault('launch_angle_from_vertical_deg', launch['launch']['launch_angle_from_vertical_deg'])
        number(row['wind_speed_mph'], 'wind speed', 0)
        number(row['launch_angle_from_vertical_deg'], 'angle from vertical', 0, 90)
        if row['payload_deployment'] not in ('deploy', 'retain') or row['recovery_configuration'] not in ('primary','secondary','tertiary'):
            raise ValueError('Unknown payload or recovery configuration')
        if not isinstance(row['name'], str) or not row['name']:
            raise ValueError('Each case needs a name')
    if len(set(c['name'] for c in rows)) != len(rows):
        raise ValueError('Duplicate case names')
    return rows


def inputs(root=ROOT):
    """Digest actual model/config bytes, not only commit IDs (also catches local edits)."""
    paths = set()
    for folder, pattern in [('config','*.json'), ('matlab','*.m'), ('vehicle','*.ork'),
                            ('vehicle','*.csv'), ('vehicle','*.eng'), ('matlab','*.csv'),
                            ('scripts','*.py'), ('openrocket','*.py')]:
        paths.update((root / folder).rglob(pattern))
    vehicle = read_json(root / 'config/vehicle.json')
    paths.add(within(root, vehicle['propulsion']['motor_file']))
    manifest = {}
    for p in sorted(paths):
        manifest[p.relative_to(root).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else 'MISSING'
    digest = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
    return digest, manifest


def provenance(root=ROOT, runtime=''):
    digest, manifest = inputs(root)
    sha = os.environ.get('GITHUB_SHA', '')
    if not sha:
        try:
            sha = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True, stderr=subprocess.DEVNULL).strip()
        except (OSError, subprocess.SubprocessError):
            sha = ''
    return dict(created_at=datetime.now(timezone.utc).isoformat(), git_commit=sha,
                input_digest=digest, input_files=manifest, runtime=runtime,
                workflow_run_id=os.environ.get('GITHUB_RUN_ID', ''))


def evaluate(requirement, value):
    if isinstance(value, bool) or not isinstance(value, (int,float)) or not math.isfinite(value):
        return 'not_evaluated'
    typ = requirement['type']
    if typ == 'range': passed = requirement['minimum'] <= value <= requirement['maximum']
    elif typ == 'minimum': passed = value >= requirement['value']
    elif typ == 'maximum': passed = value <= requirement['value']
    else: raise ValueError(f'Unknown requirement type {typ}')
    return 'pass' if passed else 'fail'
