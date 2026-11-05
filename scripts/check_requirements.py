"""CI gate: complete current results and no failed/unevaluated supported checks."""
import sys
from build_dashboard_data import build


def gate(data):
    problems=[]
    for name,model in data['models'].items():
        if model['status']!='complete': problems.append(f'{name}: {model["status"]}')
        checks=model['requirements']
        for case in data['case_definitions']:
            for rid in model['coverage']:
                matching=[c for c in checks if c.get('case_name')==case['name'] and c.get('requirement_id')==rid]
                expected=1
                if name=='matlab' and rid in ('3.2','3.10','3.11'):
                    expected=4 if case['payload_deployment']=='deploy' else 3
                if len(matching)!=expected or any(c.get('status')!='pass' for c in matching):
                    problems.append(f'{name}: {case["name"]} requirement {rid} failed or not evaluated')
    return problems

if __name__=='__main__':
    problems=gate(build())
    for item in problems[:30]: print(item)
    print(f'{len(problems)} case/requirement or coverage issues.')
    sys.exit(bool(problems))
