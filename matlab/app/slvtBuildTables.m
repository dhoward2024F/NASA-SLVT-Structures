function tables = slvtBuildTables(flight, cfg, windsMph)
%SLVTBUILDTABLES Performance, section-energy, drift and event result tables.
    if nargin < 3, windsMph = 0:5:20; end
    s = flight.Metrics;
    spec = {
        'ApogeeFt','Apogee','ft AGL';
        'TimeToApogeeS','Time to apogee','s';
        'RailExitVelocityFtS','Rail exit velocity','ft/s';
        'RailExitTimeS','Rail exit time','s';
        'MaxVelocityFtS','Maximum vertical velocity','ft/s';
        'MaxMach','Maximum Mach (vertical speed)','Mach';
        'MaxAccelerationFtS2','Maximum vertical acceleration','ft/s^2';
        'MaxNetG','Maximum net vertical G','g';
        'AverageThrustToWeight','Average thrust / liftoff weight','-';
        'PeakThrustToWeight','Peak thrust / liftoff weight','-';
        'VehicleFlightTimeS','Vehicle total flight time','s';
        'VehicleDescentTimeS','Vehicle descent from apogee','s';
        'VehicleImpactVelocityFtS','Vehicle impact speed','ft/s';
        'PayloadFlightTimeS','Payload total flight time','s';
        'PayloadDescentTimeS','Payload descent from apogee','s';
        'PayloadImpactVelocityFtS','Payload impact speed','ft/s';
        'PayloadReleaseTimeS','Payload release time','s';
        'DrogueTerminalEstimateFtS','Drogue terminal-rate estimate','ft/s';
        'MainFullyOpenEstimateFt','Main fully-open altitude estimate','ft AGL'};
    values = cellfun(@(name) s.(name), spec(:,1));
    tables.Performance = table(spec(:,2),values,spec(:,3), ...
        'VariableNames',{'Parameter','Value','Units'});
    sections = slvtSectionData(flight,cfg);
    tables.Sections = struct2table(sections(:));
    excluded = double(cfg.excludeHardwareMass);
    tables.KineticEnergy = tables.Sections(:,{'Section','LandingMassLbm','ImpactVelocityFtS','ImpactKEFtLbf'});
    groupLabels = {'Payload + forward + central';'Aft section'};
    groupMass = [cfg.payloadMassLbm+cfg.forwardMassLbm+cfg.centralMassLbm; ...
        cfg.aftMassLbm-cfg.propellantMassLbm-excluded*cfg.drogueHardwareLbm];
    tables.DrogueGroups = table(groupLabels,groupMass, ...
        repmat(s.DrogueTerminalEstimateFtS,2,1), ...
        0.5*(groupMass/cfg.g)*s.DrogueTerminalEstimateFtS^2, ...
        'VariableNames',{'TetheredGroup','MassLbm','DrogueRateFtS','DrogueKEFtLbf'});
    winds = windsMph(:);
    vehicleDrift = winds*5280/3600*s.VehicleDescentTimeS;
    payloadDrift = winds*5280/3600*s.PayloadDescentTimeS;
    tables.Drift = table(winds,vehicleDrift,payloadDrift, ...
        'VariableNames',{'WindMph','VehicleDriftFt','PayloadDriftFt'});
    tables.Events = struct2table(flight.Events(:));
end
