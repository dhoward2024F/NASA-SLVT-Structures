function results = slvtRunCases(cfg, selection, progress)
%SLVTRUNCASES Run a matrix of payload modes, recovery systems, angles and winds.
% Wind does not affect the vertical model. Store each vertical flight once.
% Example:
%   cfg = slvtDefaultConfig();
%   sel = struct('Modes',{{'Deploy','Retain'}}, 'Recoveries',1:3, ...
%                'AnglesDeg',[5 10], 'WindsMph',0:5:20);
%   results = slvtRunCases(cfg, sel);
% Optional progress(fraction,message) returns true to cancel.
    if nargin < 3, progress = @(fraction,message) false; end
    notes = slvtValidateConfig(cfg);
    if ischar(selection.Modes), selection.Modes = {selection.Modes}; end
    if isstring(selection.Modes), selection.Modes = cellstr(selection.Modes); end
    assert(~isempty(selection.Modes) && all(ismember(selection.Modes, {'Deploy','Retain'})), ...
        'SLVT:Case', 'Choose Deploy, Retain, or both.');
    assert(isnumeric(selection.Recoveries) && ~isempty(selection.Recoveries) && ...
        all(ismember(selection.Recoveries,1:3)), 'SLVT:Case', 'Choose recovery 1, 2, or 3.');
    assert(isnumeric(selection.AnglesDeg) && ~isempty(selection.AnglesDeg) && ...
        all(isfinite(selection.AnglesDeg)) && all(selection.AnglesDeg >= 0) && ...
        all(selection.AnglesDeg < 90), 'SLVT:Case', 'Angles must be in [0, 90) degrees from vertical.');
    assert(isnumeric(selection.WindsMph) && ~isempty(selection.WindsMph) && ...
        all(isfinite(selection.WindsMph)) && all(selection.WindsMph >= 0), ...
        'SLVT:Case', 'Wind speeds must be finite and nonnegative (mph).');
    selection.Modes = unique(selection.Modes, 'stable');
    selection.Recoveries = unique(selection.Recoveries(:)', 'stable');
    selection.AnglesDeg = unique(selection.AnglesDeg(:)', 'stable');
    selection.WindsMph = unique(selection.WindsMph(:)', 'stable');
    nFlights = numel(selection.Modes)*numel(selection.Recoveries)*numel(selection.AnglesDeg);
    assert(nFlights <= 100 && nFlights*numel(selection.WindsMph) <= 2000, ...
        'SLVT:Case', 'At most 100 vertical flights and 2000 wind cases per batch.');
    motor = slvtReadMotor(cfg.motorFile, cfg.motorThrustUnit);
    flights = cell(nFlights,1);
    cases = struct('CaseID',{},'Label',{},'FlightIndex',{},'Mode',{}, ...
        'Recovery',{},'LaunchAngleDeg',{},'WindMph',{});
    summaryRows = cell(0,17);
    index = 0;
    for m = 1:numel(selection.Modes)
        for r = selection.Recoveries
            for angle = selection.AnglesDeg
                index = index + 1;
                label = sprintf('%s | recovery %d | %g deg', selection.Modes{m}, r, angle);
                if progress((index-1)/nFlights,label), error('SLVT:Cancelled','Run cancelled.'); end
                f = slvtSimulate(cfg,motor,selection.Modes{m},r,angle, ...
                    @() progress((index-1)/nFlights,label));
                flights{index} = f;
                s = f.Metrics;
                for wind = selection.WindsMph
                    id = numel(cases) + 1;
                    cases(id) = struct('CaseID',id, ...
                        'Label',sprintf('%03d | %s | %g mph',id,label,wind), ...
                        'FlightIndex',index,'Mode',f.Mode,'Recovery',r, ...
                        'LaunchAngleDeg',angle,'WindMph',wind);
                    vehicleDrift = wind*5280/3600*s.VehicleDescentTimeS;
                    payloadDrift = wind*5280/3600*s.PayloadDescentTimeS;
                    summaryRows(end+1,:) = {id,f.Mode,r,angle,wind,s.ApogeeFt, ...
                        s.RailExitVelocityFtS,s.MaxMach,s.MaxVelocityFtS, ...
                        s.MaxAccelerationFtS2,s.VehicleDescentTimeS,s.PayloadDescentTimeS, ...
                        s.VehicleImpactVelocityFtS,s.PayloadImpactVelocityFtS, ...
                        vehicleDrift,payloadDrift,s.MainFullyOpenEstimateFt}; %#ok<AGROW>
                end
            end
        end
    end
    results.Config = cfg; % snapshot: later editor changes cannot alter results
    results.Selection = selection;
    results.Motor = motor;
    results.Flights = flights;
    results.Cases = cases;
    results.Notes = [notes(:); motor.Notes(:)];
    results.CreatedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    results.Summary = cell2table(summaryRows,'VariableNames', ...
        {'CaseID','PayloadMode','Recovery','LaunchAngleDeg','WindMph','ApogeeFt', ...
        'RailExitVelocityFtS','MaxMach','MaxVelocityFtS','MaxAccelerationFtS2', ...
        'VehicleDescentTimeS','PayloadDescentTimeS','VehicleImpactVelocityFtS', ...
        'PayloadImpactVelocityFtS','VehicleDriftFt','PayloadDriftFt','MainFullyOpenEstimateFt'});
    progress(1,'Complete');
end
