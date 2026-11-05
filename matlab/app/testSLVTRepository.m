function testSLVTRepository()
% Headless integration tests in MATLAB or Octave; GUI checks are separate.
    root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
    scratch=tempname(); mkdir(scratch); cleanup=onCleanup(@() rmdir(scratch,'s')); %#ok<NASGU>
    repo=fullfile(scratch,'repo with spaces'); mkdir(repo); mkdir(fullfile(repo,'config'));
    copyfile(fullfile(root,'config','*.json'),fullfile(repo,'config'));
    cfg=slvtDefaultConfig(); cfg.timeStepS=0.005;
    % A missing motor must not silently fall back to another curve.
    vehicleFile=fullfile(repo,'config','vehicle.json');
    vehicle=jsondecode(fileread(vehicleFile));
    vehicle.propulsion.motor_file='missing-test-motor.csv';
    slvtWriteJSON(vehicleFile,vehicle);
    mustFail(@() slvtReadRepository(repo),'SLVT:Repository');
    slvtSaveRepositoryModel(cfg,repo);
    plan=slvtReadRepository(repo);
    assert(abs(plan.Config.mainCd-cfg.mainCd)<1e-12);
    assert(abs(plan.Config.propellantMassLbm-cfg.propellantMassLbm)<1e-12);
    assert(numel(plan.Cases)==60);
    a=plan.Analysis; a.custom_condition.enabled=true;
    a.custom_condition.wind_speed_mph=12.3;
    a.custom_condition.launch_angle_from_vertical_deg=7.5;
    cases=slvtExpandRepositoryCases(a,plan.Launch);
    assert(numel(cases)==66);
    assert(all([cases(61:66).wind_speed_mph]==12.3));
    assert(all([cases(61:66).launch_angle_from_vertical_deg]==7.5));
    bad=a; bad.custom_condition.wind_speed_mph=[];
    mustFail(@() slvtExpandRepositoryCases(bad,plan.Launch),'');
    bad=a; bad.cases(2).name=bad.cases(1).name;
    mustFail(@() slvtExpandRepositoryCases(bad,plan.Launch),'SLVT:Case');
    slvtWriteJSON(fullfile(repo,'config','analysis_cases.json'),a);
    before=pwd;
    output=fullfile(scratch,'report output');
    [report,results]=slvtRunRepository(repo,output);
    assert(strcmp(before,pwd));
    assert(report.case_count==66 && report.unique_vertical_flights==18);
    assert(report.simulation_error_count==0 && report.not_evaluated_count==0);
    assert(numel(report.sections)==231); % 33 deploy*4 + 33 retain*3
    assert(numel(report.requirements)==957); % 66*4 vehicle + 231*3 sections
    assert(isfile(fullfile(output,'summary.json')) && isfile(fullfile(output,'inputs','matlab_model.json')));
    saved=jsondecode(fileread(fullfile(output,'summary.json')));
    assert(saved.case_count==66);
    motor=slvtReadMotor(cfg.motorFile,cfg.motorThrustUnit);
    direct=slvtSimulate(cfg,motor,'Deploy',1,5);
    assert(abs(report.cases(1).apogee_ft-direct.Metrics.ApogeeFt)<1e-9);
    sections=slvtSectionData(direct,cfg);
    assert(abs(report.sections(1).landing_kinetic_energy_ft_lbf-sections(1).ImpactKEFtLbf)<1e-9);
    assert(isequal(size(results.Flights{1}.Vehicle),size(direct.Vehicle)));
    assert(max(abs(results.Flights{1}.Vehicle(:)-direct.Vehicle(:)))<1e-8);
    % Exact bound inclusion and missing-metric behavior.
    metrics=struct('apogee_ft',4000,'thrust_to_weight_ratio',5,'rail_exit_velocity_fps',52,'max_mach',1);
    section=struct('name','fixture','landing_kinetic_energy_ft_lbf',75,'landing_drift_ft',2500,'descent_time_s',100);
    checks=slvtEvaluateRequirements(plan.Requirements.requirements,metrics,section,'bounds');
    assert(all(strcmp({checks.status},'pass')));
    metrics.apogee_ft=6000; checks=slvtEvaluateRequirements(plan.Requirements.requirements,metrics,section,'bounds');
    assert(all(strcmp({checks.status},'pass')));
    metrics.max_mach=1.001; section.landing_kinetic_energy_ft_lbf=75.1;
    checks=slvtEvaluateRequirements(plan.Requirements.requirements,metrics,section,'failure');
    assert(sum(strcmp({checks.status},'fail'))==2);
    metrics=rmfield(metrics,'max_mach'); checks=slvtEvaluateRequirements(plan.Requirements.requirements,metrics,section,'missing');
    assert(sum(strcmp({checks.status},'not_evaluated'))==1);
    % RASP units are newtons even if the CSV selector says lbf.
    motorFile=fullfile(scratch,'sample.eng');
    fid=fopen(motorFile,'w'); fprintf(fid,'; fixture\nTEST 54 200 P 0.1 0.2 Test\n0 0\n1 100\n2 0\n'); fclose(fid);
    m=slvtReadMotor(motorFile,'lbf'); assert(abs(m.ImpulseLbfS-22.48089431)<1e-9);
    fid=fopen(motorFile,'a'); fprintf(fid,'SECOND 54 200 P 0.1 0.2 Test\n'); fclose(fid);
    mustFail(@() slvtReadMotor(motorFile,'N'),'SLVT:Motor');
    % A numerical failure still exports a machine-readable report and throws.
    a.cases=a.cases(1); a.cases.launch_angle_from_vertical_deg=89.99;
    a.custom_condition.enabled=false;
    slvtWriteJSON(fullfile(repo,'config','analysis_cases.json'),a);
    mustFail(@() slvtRunRepository(repo,fullfile(scratch,'failed')),'SLVT:RepositoryRun');
    failed=jsondecode(fileread(fullfile(scratch,'failed','summary.json')));
    assert(failed.simulation_error_count==1);
    fprintf('PASS repository roundtrip, 60+6 cases, direct-engine parity, exports, limits, missing metrics, motor formats, failure reporting.\n');
end
function mustFail(action,identifier)
    caught=false;
    try, action(); catch problem, caught=isempty(identifier)||strcmp(problem.identifier,identifier); end
    assert(caught,'Expected failure %s.',identifier);
end
