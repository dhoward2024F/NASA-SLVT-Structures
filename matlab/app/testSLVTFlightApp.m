function report = testSLVTFlightApp(testUI)
%TESTSLVTFLIGHTAPP Numerical and integration checks; no test toolbox needed.
% testSLVTFlightApp(false) tests the model, case tables, drift and exports.
% testSLVTFlightApp(true) also creates/closes the MATLAB UI and settings editor.
    if nargin < 1, testUI = false; end
    cfg = slvtDefaultConfig(); slvtValidateConfig(cfg);
    motor = slvtReadMotor(cfg.motorFile,cfg.motorThrustUnit);
    assert(motor.TimeS(1) == 0 && motor.ThrustLbf(1) == 0);
    assert(abs(motor.BurnTimeS - 2.4) < 1e-12);
    assert(abs(slvtDensity(0) - 0.00237689) < 1e-8);
    cfg.timeStepS = 0.005;
    sel = struct('Modes',{{'Deploy','Retain'}},'Recoveries',1:3, ...
        'AnglesDeg',[5 10],'WindsMph',0:5:20);
    results = slvtRunCases(cfg,sel);
    assert(numel(results.Flights) == 12 && height(results.Summary) == 60);
    for k = 1:numel(results.Flights)
        f = results.Flights{k};
        assert(all(isfinite(f.Vehicle(:))) && all(diff(f.Vehicle(:,1)) > 0));
        assert(f.Vehicle(end,2) == 0 && all(f.Vehicle(:,2) >= 0));
        assert(abs(max(f.Vehicle(:,2))-f.Metrics.ApogeeFt) < 1e-9);
        tables = slvtBuildTables(f,cfg,[0 10 20]);
        assert(all(tables.Sections.ImpactKEFtLbf > 0));
        assert(all(tables.Drift.VehicleDriftFt == [0;10;20]*5280/3600*f.Metrics.VehicleDescentTimeS));
        assert(all(diff(tables.Events.TimeS) >= 0));
        if strcmp(f.Mode,'Deploy')
            release = f.Events(strcmp({f.Events.Name},'Payload release'));
            assert(abs(release.AltitudeFt-cfg.payloadDeployAltFt) < 1e-8);
            assert(all(diff(f.Payload(:,1)) > 0) && f.Payload(end,2) == 0);
            before = f.Vehicle(:,1) <= release.TimeS;
            assert(isequal(f.Vehicle(before,1:4),f.Payload(1:sum(before),1:4)));
            payloadHistory = slvtTraceTable(f.Payload,f.Metrics.TimeToApogeeS,20);
            assert(abs(payloadHistory.DriftFt(end)-tables.Drift.PayloadDriftFt(end)) < 1e-8);
        else
            assert(isempty(f.Payload) && isnan(f.Metrics.PayloadImpactVelocityFtS));
            assert(height(tables.Sections) == 3);
        end
    end
    % The recovery and payload cases must share a common ascent solution.
    apogees5 = results.Summary.ApogeeFt(results.Summary.LaunchAngleDeg == 5);
    assert(max(apogees5)-min(apogees5) < 1e-10);
    % Step-size convergence at the high-Cd main transition and payload release.
    fineCfg = cfg; fineCfg.timeStepS = 0.001;
    fine = slvtSimulate(fineCfg,motor,'Deploy',1,5);
    coarse = results.Flights{1};
    assert(abs(fine.Metrics.ApogeeFt-coarse.Metrics.ApogeeFt) < 5);
    assert(abs(fine.Metrics.VehicleImpactVelocityFtS-coarse.Metrics.VehicleImpactVelocityFtS) < 0.05);
    assert(abs(fine.Metrics.PayloadImpactVelocityFtS-coarse.Metrics.PayloadImpactVelocityFtS) < 0.05);
    % Include attached hardware: both landing mass and descent speed increase.
    attachedCfg = cfg; attachedCfg.excludeHardwareMass = false;
    attached = slvtSimulate(attachedCfg,motor,'Deploy',1,5);
    assert(attached.Metrics.VehicleImpactVelocityFtS > coarse.Metrics.VehicleImpactVelocityFtS);
    % Arbitrary launch angle and wind must produce exactly one case.
    custom = struct('Modes',{{'Retain'}},'Recoveries',2,'AnglesDeg',7.5,'WindsMph',12.3);
    one = slvtRunCases(cfg,custom);
    assert(height(one.Summary) == 1 && one.Summary.WindMph == 12.3);
    assert(abs(one.Summary.VehicleDriftFt-12.3*5280/3600*one.Summary.VehicleDescentTimeS) < 1e-8);
    invalid = cfg; invalid.aftMassLbm = 1;
    expectError(@() slvtValidateConfig(invalid),'SLVT:Config');
    expectError(@() slvtSimulate(cfg,motor,'Deploy',1,5,@() true),'SLVT:Cancelled');
    % Actual export contract: CSVs, config snapshot, and full MAT histories.
    folder = tempname; mkdir(folder); cleaner = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
    exported = slvtExportResults(one,folder,true);
    assert(exist(fullfile(exported,'case_summary.csv'),'file') == 2);
    assert(exist(fullfile(exported,'case_001_vehicle_history.csv'),'file') == 2);
    loaded = load(fullfile(exported,'SLVT_results.mat'),'results');
    assert(isequaln(loaded.results.Config,one.Config));
    settings = jsondecode(fileread(fullfile(exported,'model_settings.json')));
    assert(settings.Config.timeStepS == cfg.timeStepS);
    if testUI
        settingsFile = fullfile(folder,'ui_settings.json');
        app = SLVTFlightApp(settingsFile);
        appCleaner = onCleanup(@() delete(app)); %#ok<NASGU>
        assert(isgraphics(app.UIFigure));
        button = findall(app.UIFigure,'Type','uibutton','Text','Edit model variables...');
        feval(button.ButtonPushedFcn,button,[]);
        editor = findall(groot,'Type','figure','Name','SLVT | Edit model variables');
        assert(numel(editor) == 1);
        apply = findall(editor,'Type','uibutton','Text','Apply and save');
        feval(apply.ButtonPushedFcn,apply,[]);
        assert(exist(settingsFile,'file') == 2);
        delete(app); clear appCleaner;
        restored = SLVTFlightApp(settingsFile); restoredCleaner = onCleanup(@() delete(restored)); %#ok<NASGU>
        assert(isequaln(restored.Config,cfgWithOriginalStep(cfg)));
    end
    report = results.Summary;
    fprintf('SLVT numerical/case-table/export checks passed. UI tested: %d\n',testUI);
end

function expectError(action,identifier)
    caught = false;
    try, action(); catch problem, caught = strcmp(problem.identifier,identifier); end
    assert(caught,'Expected error %s.',identifier);
end

function cfg = cfgWithOriginalStep(cfg)
    cfg.timeStepS = 0.001;
end
