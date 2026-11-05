import copy
from http.client import HTTPConnection
import json
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from common import ROOT,cases,read_json,write_json,inputs,provenance,evaluate,within
from preflight import check
from build_dashboard_data import build
from serve_dashboard import server
from check_requirements import gate
from build_pages import package


class AutomationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        for folder in ['config','vehicle','matlab','scripts','openrocket','dashboard']:
            shutil.copytree(ROOT/folder,self.root/folder,ignore=shutil.ignore_patterns('__pycache__'))
    def tearDown(self):self.temp.cleanup()

    def test_case_matrix_and_custom_pair(self):
        standard=cases(self.root)
        self.assertEqual(len(standard),60)
        self.assertEqual(len({(c['payload_deployment'],c['recovery_configuration'],c['launch_angle_from_vertical_deg'],c['wind_speed_mph']) for c in standard}),60)
        path=self.root/'config/analysis_cases.json';a=read_json(path)
        a['custom_condition'].update(enabled=True,wind_speed_mph=12.3,launch_angle_from_vertical_deg=7.5)
        write_json(path,a); expanded=cases(self.root)
        self.assertEqual(len(expanded),66)
        self.assertEqual({(c['wind_speed_mph'],c['launch_angle_from_vertical_deg']) for c in expanded[60:]},{(12.3,7.5)})
        a['custom_condition']['wind_speed_mph']=None;write_json(path,a)
        with self.assertRaises(ValueError):cases(self.root)

    def test_limits_missing_and_invalid_cases(self):
        r={'type':'range','minimum':4000,'maximum':6000}
        self.assertEqual(evaluate(r,4000),'pass');self.assertEqual(evaluate(r,6000),'pass')
        self.assertEqual(evaluate(r,3999),'fail');self.assertEqual(evaluate(r,None),'not_evaluated')
        self.assertEqual(evaluate(r,float('nan')),'not_evaluated')
        path=self.root/'config/analysis_cases.json';a=read_json(path)
        a['cases'][1]['name']=a['cases'][0]['name'];write_json(path,a)
        with self.assertRaises(ValueError):cases(self.root)
        with self.assertRaises(ValueError):within(self.root,'../outside')

    def fixture_report(self,model):
        definitions=cases(self.root)
        report=dict(status='complete',provenance=provenance(self.root,'test fixture'),
            cases=[dict(case_name=c['name'],run_status='ok',**{k:v for k,v in c.items() if k!='name'}) for c in definitions],
            supported_requirements=['2.1','2.14','2.20.6'] if model=='openrocket' else [r['id'] for r in read_json(self.root/'config/requirements.json')['requirements']],
            requirements=[],sections=[],simulation_error_count=0)
        for c in definitions:
            for rid in report['supported_requirements']:
                count=(4 if c['payload_deployment']=='deploy' else 3) if model=='matlab' and rid in ('3.2','3.10','3.11') else 1
                for i in range(count):
                    report['requirements'].append(dict(case_name=c['name'],requirement_id=rid,section=str(i),status='pass'))
            if model=='matlab':
                report['sections'].extend(dict(case_name=c['name'],name=str(i)) for i in range(4 if c['payload_deployment']=='deploy' else 3))
        write_json(self.root/'results'/model/'summary.json',report)
        return report

    def test_missing_stale_and_failed_not_pass(self):
        data=build(self.root)
        self.assertEqual(data['status'],'incomplete');self.assertTrue(gate(data))
        self.fixture_report('matlab');self.fixture_report('openrocket')
        self.assertEqual(build(self.root)['status'],'complete');self.assertFalse(gate(build(self.root)))
        path=self.root/'config/vehicle.json';v=read_json(path);v['mass']['liftoff_lbm']=60;write_json(path,v)
        self.assertEqual(build(self.root)['models']['matlab']['status'],'stale');self.assertTrue(gate(build(self.root)))
        report=self.fixture_report('matlab');report['cases'].pop();write_json(self.root/'results/matlab/summary.json',report)
        self.assertEqual(build(self.root)['models']['matlab']['status'],'incomplete')
        report['status']='error';write_json(self.root/'results/matlab/summary.json',report)
        self.assertEqual(build(self.root)['models']['matlab']['status'],'error')
        report=self.fixture_report('matlab');report['requirements'].pop();write_json(self.root/'results/matlab/summary.json',report)
        self.assertEqual(build(self.root)['models']['matlab']['status'],'incomplete')
        report=self.fixture_report('matlab');report['sections'].pop();write_json(self.root/'results/matlab/summary.json',report)
        self.assertEqual(build(self.root)['models']['matlab']['status'],'incomplete')
        path.write_text('{broken json')
        self.assertEqual(build(self.root)['status'],'incomplete')

    def test_hash_tracks_motor_and_rejects_nonstandard_json(self):
        first=inputs(self.root)[0]
        p=self.root/'vehicle/openrocket/motors/AeroTech_L2200G.csv';p.write_text(p.read_text()+'\n')
        self.assertNotEqual(first,inputs(self.root)[0])
        p=self.root/'bad.json';p.write_text('{"value":NaN}')
        with self.assertRaises(ValueError):read_json(p)

    def test_current_inputs_pass_preflight(self):
        self.assertEqual(len(check(self.root)),60)

    def test_pages_package_contains_only_dashboard_and_results(self):
        report=self.fixture_report('matlab');self.fixture_report('openrocket')
        report['provenance']['input_files']={'private_source':'DO_NOT_PUBLISH'}
        report['requirements'][0]['status']='fail'
        write_json(self.root/'results/matlab/summary.json',report)
        target=self.root/'_site';target.mkdir();(target/'old-private-file').write_text('DO_NOT_PUBLISH')
        self.assertFalse(package(self.root))
        self.assertEqual({p.name for p in target.iterdir()},{'index.html','app.js','styles.css','data.json','.nojekyll'})
        self.assertIn('data-hosting="pages"',(target/'index.html').read_text())
        raw=(target/'data.json').read_text();self.assertNotIn('DO_NOT_PUBLISH',raw)
        data=read_json(target/'data.json')
        self.assertEqual(data['models']['matlab']['status'],'complete')
        self.assertEqual(data['models']['matlab']['requirements'][0]['status'],'fail')
        self.assertNotIn('input_files',data['models']['matlab']['provenance'])
        self.assertEqual(data['publication']['repository'],'dhoward2024F/NASA-SLVT-Structures')

    def test_pages_preserves_missing_results_and_requires_explicit_opt_in(self):
        self.assertFalse(package(self.root))
        self.assertEqual(read_json(self.root/'_site/data.json')['models']['matlab']['status'],'missing')
        path=self.root/'config/automation.json';cfg=read_json(path)
        cfg['pages']['enabled']='true';write_json(path,cfg)
        with self.assertRaises(ValueError): package(self.root)
        cfg['pages']['enabled']=True;write_json(path,cfg)
        self.assertTrue(package(self.root))


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.http,self.url=server(port=0,token='test-session-token')
        self.thread=threading.Thread(target=self.http.serve_forever,daemon=True);self.thread.start()
    def tearDown(self):
        self.http.shutdown();self.http.server_close();self.thread.join()
    def get(self,path,headers=None):
        con=HTTPConnection('127.0.0.1',self.http.server_port);con.request('GET',path,headers=headers or {})
        response=con.getresponse();data=response.read();status=response.status;hdrs=dict(response.getheaders());con.close();return status,hdrs,data
    def test_loopback_auth_host_and_file_isolation(self):
        self.assertEqual(self.http.server_address[0],'127.0.0.1')
        self.assertEqual(self.get('/api/dashboard')[0],401)
        self.assertEqual(self.get('/?token=wrong')[0],401)
        status,headers,_=self.get('/?token=test-session-token');self.assertEqual(status,303)
        self.assertIn('HttpOnly',headers['Set-Cookie']);self.assertIn('SameSite=Strict',headers['Set-Cookie'])
        auth={'Cookie':'slvt_session=test-session-token'}
        self.assertEqual(self.get('/',auth)[0],200)
        self.assertEqual(self.get('/api/dashboard',auth)[0],200)
        self.assertEqual(self.get('/config/vehicle.json',auth)[0],404)
        self.assertEqual(self.get('/../.git/config',auth)[0],404)
        self.assertEqual(self.get('/api/dashboard',{**auth,'Host':'attacker.invalid'})[0],403)
        self.assertIn("default-src 'self'",self.get('/',auth)[1]['Content-Security-Policy'])

if __name__=='__main__':unittest.main()
