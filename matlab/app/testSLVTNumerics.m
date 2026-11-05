function report = testSLVTNumerics()
%TESTSLVTNUMERICS Test the actual numerical engine in MATLAB or GNU Octave.
% This test does not require graphics or MATLAB table support.
    cfg = slvtDefaultConfig(); cfg.timeStepS = 0.005;
    slvtValidateConfig(cfg);
    motor = slvtReadMotor(cfg.motorFile,cfg.motorThrustUnit);
    assert(motor.TimeS(1) == 0 && motor.ThrustLbf(1) == 0);
    assert(abs(motor.BurnTimeS - 2.4) < 1e-12);
    assert(abs(slvtDensity(0)-0.00237689) < 1e-8);
    assert(slvtDensity(5000) < slvtDensity(800));
    modes = {'Deploy','Retain'};
    report = struct('Mode',{},'Recovery',{},'AngleDeg',{},'Metrics',{});
    flights = cell(12,1); index = 0;
    for m = 1:2
        for recovery = 1:3
            for angle = [5 10]
                index = index + 1;
                f = slvtSimulate(cfg,motor,modes{m},recovery,angle);
                flights{index} = f;
                assert(all(isfinite(f.Vehicle(:))) && all(diff(f.Vehicle(:,1)) > 0));
                assert(f.Vehicle(end,2) == 0 && all(f.Vehicle(:,2) >= 0));
                assert(abs(max(f.Vehicle(:,2))-f.Metrics.ApogeeFt) < 1e-8);
                assert(all(diff([f.Events.TimeS]) >= 0));
                beforeChute = f.Vehicle(f.Vehicle(:,6) == 3,:);
                assert(all(abs(beforeChute(:,4) + cfg.g) < 1e-10));
                drogue = f.Vehicle(f.Vehicle(:,6) == 4,:);
                expectedMass = cfg.totalMassLbm - cfg.propellantMassLbm - cfg.drogueHardwareLbm;
                assert(all(abs(drogue(:,5)-expectedMass) < 1e-9));
                main = f.Events(strcmp({f.Events.Name},'Main fully open (altitude estimate)'));
                assert(abs(main.AltitudeFt-f.Metrics.MainFullyOpenEstimateFt) < 1e-8);
                if strcmp(f.Mode,'Deploy')
                    release = f.Events(strcmp({f.Events.Name},'Payload release'));
                    assert(abs(release.AltitudeFt-cfg.payloadDeployAltFt) < 1e-8);
                    assert(all(isfinite(f.Payload(:))) && all(diff(f.Payload(:,1)) > 0));
                    assert(f.Payload(end,2) == 0 && all(f.Payload(:,2) >= 0));
                    before = f.Vehicle(:,1) <= release.TimeS;
                    assert(isequal(f.Vehicle(before,1:4),f.Payload(1:sum(before),1:4)));
                    chute = f.Events(strcmp({f.Events.Name},'Payload parachute fully open'));
                    assert(abs(chute.TimeS-release.TimeS-cfg.payloadOpenS) < 1e-9);
                    assert(f.Metrics.PayloadFlightTimeS > release.TimeS);
                else
                    assert(isempty(f.Payload) && isnan(f.Metrics.PayloadImpactVelocityFtS));
                end
                % Verify stored accelerations are the actual Newton update.
                selected = find(f.Vehicle(:,6) == 4,1,'last');
                previous = f.Vehicle(selected-1,:); current = f.Vehicle(selected,:);
                area = pi*cfg.drogueDiameterFt^2/4;
                rho = slvtDensity(previous(2)+cfg.siteAltitudeFt);
                force = -0.5*rho*cfg.drogueCd*area*previous(3)*abs(previous(3));
                expectedA = force/(current(5)/cfg.g)-cfg.g;
                assert(abs(current(4)-expectedA) < 1e-9);
                report(index) = struct('Mode',f.Mode,'Recovery',recovery,'AngleDeg',angle,'Metrics',f.Metrics);
                fprintf('PASS %s R%d %g deg | apogee %.2f ft | impact %.3f ft/s\n', ...
                    f.Mode,recovery,angle,f.Metrics.ApogeeFt,f.Metrics.VehicleImpactVelocityFtS);
            end
        end
    end
    sameAscent = [report(1:2:end).Metrics];
    assert(max([sameAscent.ApogeeFt])-min([sameAscent.ApogeeFt]) < 1e-9);
    assert(flights{1}.Metrics.VehicleImpactVelocityFtS < flights{7}.Metrics.VehicleImpactVelocityFtS);
    fineCfg = cfg; fineCfg.timeStepS = 0.001;
    fine = slvtSimulate(fineCfg,motor,'Deploy',1,5);
    coarse = flights{1};
    assert(abs(fine.Metrics.ApogeeFt-coarse.Metrics.ApogeeFt) < 5);
    assert(abs(fine.Metrics.VehicleImpactVelocityFtS-coarse.Metrics.VehicleImpactVelocityFtS) < 0.05);
    assert(abs(fine.Metrics.PayloadImpactVelocityFtS-coarse.Metrics.PayloadImpactVelocityFtS) < 0.05);
    fprintf('PASS dt convergence | apogee difference %.4f ft | vehicle impact difference %.6f ft/s\n', ...
        abs(fine.Metrics.ApogeeFt-coarse.Metrics.ApogeeFt), ...
        abs(fine.Metrics.VehicleImpactVelocityFtS-coarse.Metrics.VehicleImpactVelocityFtS));
    attachedCfg = cfg; attachedCfg.excludeHardwareMass = false;
    attached = slvtSimulate(attachedCfg,motor,'Deploy',1,5);
    assert(attached.Metrics.VehicleImpactVelocityFtS > coarse.Metrics.VehicleImpactVelocityFtS);
    custom = slvtSimulate(cfg,motor,'Retain',2,7.5);
    assert(custom.Metrics.ApogeeFt < flights{7}.Metrics.ApogeeFt);
    assert(custom.Metrics.ApogeeFt > flights{8}.Metrics.ApogeeFt);
    invalid = cfg; invalid.aftMassLbm = 1;
    mustFail(@() slvtValidateConfig(invalid),'SLVT:Config');
    mustFail(@() slvtSimulate(cfg,motor,'Deploy',1,5,@() true),'SLVT:Cancelled');
    late = cfg; late.mainOpenS = 100;
    mustFail(@() slvtSimulate(late,motor,'Deploy',1,5),'SLVT:Schedule');
    fprintf('PASS custom angle, hardware option, mass checks, cancellation, and invalid schedule\n');
    fprintf('All SLVT engine checks passed. GUI/table/export checks require MATLAB.\n');
end

function mustFail(action,identifier)
    caught = false;
    try, action(); catch problem, caught = strcmp(problem.identifier,identifier); end
    assert(caught,'Expected error %s.',identifier);
end
