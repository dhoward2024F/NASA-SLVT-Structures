function motor = slvtReadMotor(filename, thrustUnit)
%SLVTREADMOTOR Read two numeric CSV columns after optional metadata/header rows.
% Column 1: time in seconds. Column 2: thrust in N or lbf as specified.
    if nargin < 2, thrustUnit = 'N'; end
    fid = fopen(filename, 'r');
    assert(fid >= 0, 'SLVT:Motor', 'Cannot open motor CSV: %s', char(filename));
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    [~,~,extension] = fileparts(filename);
    rasp = strcmpi(extension,'.eng');
    headerSeen = false;
    if rasp, thrustUnit = 'N'; end
    samples = zeros(0, 2);
    lineNumber = 0;
    while true
        line = fgetl(fid);
        if ~ischar(line), break; end
        lineNumber = lineNumber + 1;
        line = strtrim(strrep(line, '"', ''));
        if isempty(line) || line(1) == '#', continue; end

        if rasp
            if line(1)==';', continue; end
            parts=regexp(line,'\s+','split');
            if ~headerSeen
                assert(numel(parts)>=7,'SLVT:Motor','Invalid RASP header.');
                headerSeen=true; continue;
            end
            assert(numel(parts)==2,'SLVT:Motor','Use a single-motor RASP .eng file; unexpected header or row at line %d.',lineNumber);
        else
            parts = strsplit(line, ',');
        end

        if numel(parts) < 2, continue; end
        time = str2double(strtrim(parts{1}));
        thrust = str2double(strtrim(parts{2}));
        if isnan(time) && ~any(strcmpi(strtrim(parts{1}), {'nan','inf','-inf'}))
            assert(~rasp,'SLVT:Motor','Invalid RASP data row at line %d.',lineNumber);
            continue; % title, source URL, column header, etc.
        end
        assert(isfinite(time) && isfinite(thrust) && time >= 0 && thrust >= 0, ...
            'SLVT:Motor', 'Invalid time/thrust at CSV line %d.', lineNumber);
        samples(end+1, :) = [time thrust]; %#ok<AGROW>
    end
    assert(size(samples,1) >= 2, 'SLVT:Motor', ...
        'Motor CSV must contain at least two numeric time/thrust rows.');
    assert(all(diff(samples(:,1)) > 0), 'SLVT:Motor', ...
        'Motor times must be strictly increasing; remove duplicates or reorder rows.');
    assert(samples(end,1) > 0 && any(samples(:,2) > 0), 'SLVT:Motor', ...
        'Motor must have a positive duration and nonzero thrust.');
    motor.Notes = {};
    if samples(1,1) > 0
        samples = [0 0; samples];
        motor.Notes{end+1} = 'Added (0 s, 0 thrust) before the first motor sample.';
    end
    if samples(end,2) ~= 0
        motor.Notes{end+1} = ['Last motor sample is nonzero. The motor stops at the final timestamp; ' ...
            'include a final zero-thrust row if that is not intended.'];
    end
    switch thrustUnit
        case 'N', thrustLbf = samples(:,2) * 0.2248089431;
        case 'lbf', thrustLbf = samples(:,2);
        otherwise, error('SLVT:Motor', 'Thrust units must be N or lbf.');
    end
    motor.File = char(filename);
    motor.TimeS = samples(:,1);
    motor.ThrustLbf = thrustLbf;
    motor.BurnTimeS = motor.TimeS(end);
    motor.ImpulseLbfS = trapz(motor.TimeS, motor.ThrustLbf);
    motor.PeakThrustLbf = max(motor.ThrustLbf);
    motor.AverageThrustLbf = motor.ImpulseLbfS / motor.BurnTimeS;
end
