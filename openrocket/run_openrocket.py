"""Run the selected .ork with OpenRocket 24.12; preserve source design and recovery settings.
Only ascent metrics are used for comparison. Deployment/recovery scenarios belong to MATLAB.
"""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from common import ROOT, cases, read_json, write_json, provenance, within, evaluate
from fetch_openrocket import fetch
import math
import zipfile
import xml.etree.ElementTree as ET

SUPPORTED = ['2.1','2.14','2.20.6']


def run(root=ROOT):
    import jpype
    config=read_json(root/'config/automation.json')['openrocket']
    launch=read_json(root/'config/launch_conditions.json')
    vehicle=read_json(root/'config/vehicle.json')
    fallbacks=read_json(root/'config/matlab_model.json')['fallbacks']
    requirements=read_json(root/'config/requirements.json')['requirements']
    definitions=cases(root)
    source=within(root,config['model_file'])
    with zipfile.ZipFile(source) as archive:
        tree=ET.fromstring(archive.read('rocket.ork'))
    # Do not execute arbitrary stored simulation extensions or external plugins in CI.
    if tree.findall('.//extension') or tree.findall('.//simulationextension'):
        raise ValueError('Stored simulation extensions need a reviewed adapter before automated execution')
    jar=fetch(root)
    if jpype.isJVMStarted(): raise RuntimeError('Run OpenRocket in its own Python process')
    prefs=root/'.tools'/'java-prefs';prefs.mkdir(parents=True,exist_ok=True)
    jpype.startJVM('-Djava.awt.headless=true','-Dopenrocket.bypass.presets=true',
                  '-Dopenrocket.locale=en_US',f'-Djava.util.prefs.userRoot={prefs}',
                  classpath=[str(jar)],convertStrings=True)
    try:
        J=jpype.JClass
        J('org.slf4j.LoggerFactory').getLogger('ROOT').setLevel(J('ch.qos.logback.classic.Level').ERROR)
        # Explicit bindings compensate for CoreModule's incomplete 24.12 wiring,
        # and avoid dynamic Swing/plugin scanning through JPype's class loader.
        def configure(binder):
            J('com.google.inject.multibindings.Multibinder').newSetBinder(
                binder,J('info.openrocket.core.formatting.RocketSubstitutor').class_).addBinding().to(
                J('info.openrocket.core.formatting.MotorConfigurationSubstitutor').class_)
            binder.bind(J('info.openrocket.core.database.ComponentPresetDao').class_).to(
                J('info.openrocket.core.database.ComponentPresetDatabase').class_)
        module=J('info.openrocket.core.startup.CoreModule')()
        bindings=jpype.JProxy('com.google.inject.Module',dict(configure=configure))
        injector=J('com.google.inject.Guice').createInjector(jpype.JArray(J('com.google.inject.Module'))([module,bindings]))
        J('info.openrocket.core.startup.Application').setInjector(injector)
        module.startLoader()
        loader=J('info.openrocket.core.file.GeneralRocketLoader')(J('java.io.File')(str(source)))
        doc=loader.load()
        sim=doc.getSimulation(config['simulation_index'])
        motors=[str(m.getMotor().getDesignation()) for m in sim.getActiveConfiguration().getActiveMotors()]
        if not motors or any(vehicle['propulsion']['motor_name'] not in name for name in motors):
            raise ValueError(f'OpenRocket motor(s) {motors} do not match vehicle.json {vehicle["propulsion"]["motor_name"]}')
        options=sim.getOptions()
        for field,setter in [('latitude_deg','setLaunchLatitude'),('longitude_deg','setLaunchLongitude')]:
            if launch['launch_site'][field] is not None: getattr(options,setter)(launch['launch_site'][field])
        elevation=launch['launch_site'].get('elevation_ft')
        rail=launch['launch'].get('rail_length_ft')
        options.setLaunchAltitude((fallbacks['siteAltitudeFt'] if elevation is None else elevation)*0.3048)
        options.setLaunchRodLength((fallbacks['railLengthFt'] if rail is None else rail)*0.3048)
        options.setMaxSimulationTime(600)
        options.setRandomSeed(config['random_seed'])
        cache={}; rows=[]; checks=[]; histories=[]
        notes=[str(w) for w in loader.getWarnings()]
        notes += [
            'Fresh OpenRocket simulations, not cached values embedded in the .ork file.',
            'Ascent reference only: geometry, mass, motor and recovery definitions come from the selected .ork. Shared vehicle geometry/mass JSON values do not modify it.',
            'Payload deploy/retain and recovery 1/2/3 labels reuse the same ascent solution; these configurations are not separately modeled in OpenRocket.',
            'The MATLAB model supplies section landing energy, descent time, drift and average thrust-to-weight checks.',
            'Zero turbulence with a fixed seed. Wind direction and rail azimuth are retained from the .ork; temperature/pressure follow its atmosphere model.'
        ]
        F=J('info.openrocket.core.simulation.FlightDataType')
        for d in definitions:
            key=(d['launch_angle_from_vertical_deg'],d['wind_speed_mph'])
            if key not in cache:
                print(f'OpenRocket: {key[0]} deg / {key[1]} mph',flush=True)
                options.setLaunchRodAngle(math.radians(key[0]))
                options.setWindSpeedAverage(key[1]*0.44704)
                options.setWindTurbulenceIntensity(config['turbulence_intensity'])
                sim.simulate()
                data=sim.getSimulatedData(); branch=data.getBranch(0)
                events={e.getType().name():float(e.getTime()) for e in branch.getEvents()}
                if 'SIM_ABORT' in events or 'APOGEE' not in events or 'LAUNCHROD' not in events:
                    raise ValueError(f'OpenRocket did not complete ascent: {events}')
                times=list(branch.get(F.TYPE_TIME)); alt=list(branch.get(F.TYPE_ALTITUDE))
                mach=list(branch.get(F.TYPE_MACH_NUMBER))
                valid=[float(m) for t,m in zip(times,mach) if t<=events['APOGEE'] and math.isfinite(m)]
                row=dict(apogee_ft=float(data.getMaxAltitude())/0.3048,
                         rail_exit_velocity_fps=float(data.getLaunchRodVelocity())/0.3048,
                         max_mach=max(valid),max_velocity_fps=float(data.getMaxVelocity())/0.3048)
                if not all(math.isfinite(x) for x in row.values()): raise ValueError('Nonfinite OpenRocket output')
                cache[key]=row
                stride=max(1,len(times)//200)
                histories.append(dict(angle=key[0],wind=key[1],points=[
                    [round(float(times[i]),3),round(float(alt[i])/0.3048,2)]
                    for i in range(0,len(times),stride) if math.isfinite(alt[i])]))
                notes.extend(str(w) for w in data.getWarningSet())
            row=dict(case_name=d['name'],**{k:v for k,v in d.items() if k!='name'},
                     **cache[key],run_status='ok',error='',coverage='shared_ascent')
            rows.append(row)
            for r in requirements:
                if r['id'] in SUPPORTED:
                    checks.append(dict(case_name=d['name'],requirement_id=r['id'],section='launch_vehicle',
                                       metric=r['metric'],value=row.get(r['metric']),units=r['units'],
                                       status=evaluate(r,row.get(r['metric']))))
        report=dict(schema_version=1,assessment='ascent_reference',case_count=len(rows),
                    unique_simulations=len(cache),supported_requirements=SUPPORTED,cases=rows,
                    sections=[],requirements=checks,histories=histories,notes=list(dict.fromkeys(notes)),
                    source_model=config['model_file'],motors=motors,simulation_error_count=0,
                    provenance=provenance(root,'OpenRocket 24.12 / Java 17'),status='complete')
        write_json(root/'results/openrocket/summary.json',report)
    finally:
        jpype.shutdownJVM()

if __name__=='__main__': run()
