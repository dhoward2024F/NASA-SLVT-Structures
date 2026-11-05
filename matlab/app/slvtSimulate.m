function flight = slvtSimulate(cfg, motor, mode, recovery, angleDeg, cancelCheck)
%SLVTSIMULATE Shared staged Newton/kinematics engine for deploy and retain.
% No tables, graphics, or workspace side effects; usable independently.
% Trace columns: [time_s altitude_ft verticalVelocity_ft_s acceleration_ft_s2
%                 suspendedMass_lbm phaseCode]. Wind is applied separately.
% Phase codes: 1 powered, 2 coast, 3 pre-drogue, 4 drogue, 5 main,
%              6 main after payload release, 7 payload free fall, 8 payload chute.
    if nargin < 6, cancelCheck = @() false; end
    slvtValidateConfig(cfg);
    assert(any(strcmp(mode, {'Deploy','Retain'})), 'SLVT:Case', 'Mode must be Deploy or Retain.');
    assert(isscalar(recovery) && any(recovery == [1 2 3]), 'SLVT:Case', 'Recovery must be 1, 2, or 3.');
    assert(isscalar(angleDeg) && isfinite(angleDeg) && angleDeg >= 0 && angleDeg < 90, ...
        'SLVT:Case', 'Launch angle must be in [0, 90) degrees from vertical.');
    assert(motor.BurnTimeS < cfg.maxTimeS, 'SLVT:Case', 'Maximum time is shorter than the motor burn.');
    deploying = strcmp(mode, 'Deploy');
    totalLbm = cfg.totalMassLbm;
    if cfg.useSectionTotal
        totalLbm = cfg.payloadMassLbm + cfg.forwardMassLbm + cfg.centralMassLbm + cfg.aftMassLbm;
    end
    g = cfg.g; dt = cfg.timeStepS; cosine = cos(angleDeg * pi / 180);
    bodyArea = pi * (cfg.bodyDiameterIn / 12)^2 / 4 + ...
        cfg.finCount * cfg.finHeightIn * cfg.finThicknessIn / 144;
    drogueArea = pi * cfg.drogueDiameterFt^2 / 4;
    mainArea = pi * cfg.mainDiameterFt^2 / 4;
    payloadArea = pi * cfg.payloadDiameterFt^2 / 4;
    removedDrogue = double(cfg.excludeHardwareMass) * cfg.drogueHardwareLbm;
    removedMain = double(cfg.excludeHardwareMass) * cfg.mainHardwareLbm;
    removedPayloadHardware = double(cfg.excludeHardwareMass) * cfg.payloadHardwareLbm;
    mass = totalLbm / g;
    dryMass = (totalLbm - cfg.propellantMassLbm) / g;
    phase = 1; t = 0; h = 0; v = 0; a = 0;
    capacity = min(ceil(180 / dt) + 16, ceil(cfg.maxTimeS / dt) + 16);
    vehicle = zeros(capacity, 6); n = 1;
    vehicle(n,:) = [0 0 0 0 totalLbm 1];
    events = struct('Name', {}, 'Body', {}, 'TimeS', {}, 'AltitudeFt', {}, 'VelocityFtS', {});
    addEvent('Launch / ignition', 'Vehicle', t, h, v);
    railTime = NaN; railVelocity = NaN;
    apogee = NaN; apogeeTime = NaN; drogueOpenTime = NaN;
    mainOpenAltitude = NaN; vtDrogue = NaN; apogeeIndex = NaN;
    payloadStart = []; releaseIndex = NaN; mainCommandRecorded = false;
    burnTimes = (dt:dt:motor.BurnTimeS)';
    if isempty(burnTimes) || motor.BurnTimeS - burnTimes(end) > 1e-10
        burnTimes(end+1,1) = motor.BurnTimeS;
    end
    burnTimes = min(burnTimes,motor.BurnTimeS);
    burnThrust = interp1(motor.TimeS, motor.ThrustLbf, burnTimes, 'linear');
    burnIndex = 0;

    while h > 0 || phase <= 2
        if phase == 1
            burnIndex = burnIndex + 1;
            step = burnTimes(burnIndex) - t;
            mass = (totalLbm - cfg.propellantMassLbm * t / motor.BurnTimeS) / g;
            drag = dragForce(cfg.bodyCd * bodyArea, h, v);
            a = (burnThrust(burnIndex) + drag) * cosine / mass - g;
            advanceVehicle(step, a, 1, true);
            if burnIndex == numel(burnTimes)
                mass = dryMass;
                phase = 2;
                vehicle(n,5) = mass * g;
                addEvent('Motor burnout', 'Vehicle', t, h, v);
                assert(h > 0 && v > 0, 'SLVT:NoLaunch', ...
                    'Vehicle did not complete a normal powered ascent. Check motor, mass, and angle.');
                assert(isfinite(railTime), 'SLVT:NoRailExit', ...
                    'Vehicle did not leave the effective rail before burnout.');
            end
        elseif phase == 2
            a = dragForce(cfg.bodyCd * bodyArea, h, v) * cosine / mass - g;
            step = dt;
            if v + a * step <= 0, step = -v / a; end
            advanceVehicle(step, a, 2, false);
            if v <= 1e-8
                v = 0; vehicle(n,3) = 0;
                apogee = h; apogeeTime = t; apogeeIndex = n;
                addEvent('Apogee', 'Vehicle', t, h, v);
                drogueOpenTime = t + cfg.drogueDelayS(recovery) + cfg.drogueOpenS;
                phase = 3;
            end
        elseif phase == 3
            if t < drogueOpenTime - 1e-10
                advanceVehicle(min(dt, drogueOpenTime - t), -g, 3, false);
                assert(h > 0, 'SLVT:Schedule', 'Vehicle hit the ground before the drogue opened.');
            else
                mass = mass - removedDrogue / g;
                % Preserve the original main-opening estimate, including its
                % use of AGL altitude in this one terminal-rate calculation.
                vtDrogue = sqrt(2 * mass * g / ...
                    (slvtDensity(h, cfg.atmosphere) * cfg.drogueCd * drogueArea));
                mainOpenAltitude = cfg.mainDeployAltFt(recovery) - cfg.mainOpenS * vtDrogue;
                assert(mainOpenAltitude > 0, 'SLVT:Schedule', ...
                    'Estimated main fully-open altitude is %.2f ft. Increase main altitude or reduce opening time.', ...
                    mainOpenAltitude);
                assert(apogee > cfg.mainDeployAltFt(recovery), 'SLVT:Schedule', ...
                    'Apogee is below the selected main deployment altitude.');
                assert(h > cfg.mainDeployAltFt(recovery), 'SLVT:Schedule', ...
                    'Drogue opens below the main command altitude. Reduce drogue delay or main altitude.');
                if deploying
                    assert(mainOpenAltitude > cfg.payloadDeployAltFt, 'SLVT:Schedule', ...
                        ['Estimated main fully-open altitude (%.2f ft) must exceed payload release altitude ' ...
                         '(%.2f ft) for the original sequence.'], mainOpenAltitude, cfg.payloadDeployAltFt);
                end
                addEvent('Drogue fully open', 'Vehicle', t, h, v);
                phase = 4;
            end
        elseif phase == 4
            if h <= mainOpenAltitude + 1e-9
                mass = mass - removedMain / g;
                addEvent('Main fully open (altitude estimate)', 'Vehicle', t, h, v);
                phase = 5;
            else
                a = dragForce(cfg.drogueCd * drogueArea, h, v) / mass - g;
                step = timeToAltitude(mainOpenAltitude, a, dt);
                oldT = t; oldH = h; oldV = v;
                advanceVehicle(step, a, 4, false);
                if ~mainCommandRecorded && h <= cfg.mainDeployAltFt(recovery)
                    tau = crossingTime(oldH, oldV, a, cfg.mainDeployAltFt(recovery), step);
                    addEvent('Main deployment command', 'Vehicle', oldT + tau, ...
                        cfg.mainDeployAltFt(recovery), oldV + a * tau);
                    mainCommandRecorded = true;
                end
            end
        elseif phase == 5 || phase == 6
            target = 0;
            if deploying && phase == 5, target = cfg.payloadDeployAltFt; end
            if h <= target + 1e-9 && target > 0
                payloadStart = [t h v]; releaseIndex = n;
                addEvent('Payload release', 'Payload', t, h, v);
                mass = mass - cfg.payloadMassLbm / g;
                phase = 6;
            else
                a = dragForce(cfg.drogueCd * drogueArea + cfg.mainCd * mainArea, h, v) / mass - g;
                advanceVehicle(timeToAltitude(target, a, dt), a, phase, false);
            end
        end
    end
    vehicle(n,2) = 0; h = 0;
    addEvent('Vehicle touchdown', 'Vehicle', t, h, v);
    vehicle = vehicle(1:n,:);

    payload = [];
    if deploying
        assert(~isempty(payloadStart), 'SLVT:Schedule', 'Payload release altitude was not reached.');
        % Payload shares all pre-release states, then follows its own clock.
        payload = zeros(capacity,6);
        payload(1:releaseIndex,:) = vehicle(1:releaseIndex,:);
        payload(1:releaseIndex,5) = cfg.payloadMassLbm;
        np = releaseIndex;
        pt = payloadStart(1); ph = payloadStart(2); pv = payloadStart(3);
        pm = cfg.payloadMassLbm / g;
        openTime = pt + cfg.payloadOpenS;
        opened = false;
        while ph > 0
            if ~opened && pt >= openTime - 1e-10
                pm = (cfg.payloadMassLbm - removedPayloadHardware) / g;
                addEvent('Payload parachute fully open', 'Payload', pt, ph, pv);
                opened = true;
            end
            step = dt;
            if ~opened
                pa = -g;
                step = min(step, openTime - pt);
                code = 7;
            else
                pa = dragForce(cfg.payloadCd * payloadArea, ph, pv) / pm - g;
                code = 8;
            end
            newH = ph + pv * step + 0.5 * pa * step^2;
            if newH <= 0, step = crossingTime(ph, pv, pa, 0, step); end
            ph = max(0, ph + pv * step + 0.5 * pa * step^2);
            if ph < 1e-8, ph = 0; end
            pv = pv + pa * step; pt = pt + step;
            assert(isfinite(ph) && isfinite(pv) && isfinite(pt), ...
                'SLVT:Numerics','Nonfinite payload flight state.');
            assert(pv <= 1e-6, 'SLVT:StepSize', 'Payload integration became unstable. Reduce time step.');
            np = np + 1;
            if np > size(payload,1), payload(end+capacity,6) = 0; end
            payload(np,:) = [pt ph pv pa pm*g code];
            checkRun(pt, np);
        end
        payload = payload(1:np,:);
        payload(end,2) = 0;
        addEvent('Payload touchdown', 'Payload', pt, 0, pv);
    end
    % Add the drogue trigger separately from full opening and sort the log.
    triggerTime = apogeeTime + cfg.drogueDelayS(recovery);
    addEvent('Drogue deployment command', 'Vehicle', triggerTime, ...
        interp1(vehicle(:,1), vehicle(:,2), triggerTime), ...
        interp1(vehicle(:,1), vehicle(:,3), triggerTime));
    [~, order] = sort([events.TimeS]); events = events(order);
    metrics.ApogeeFt = apogee;
    metrics.TimeToApogeeS = apogeeTime;
    metrics.RailExitVelocityFtS = railVelocity;
    metrics.RailExitTimeS = railTime;
    metrics.MaxVelocityFtS = max(vehicle(1:apogeeIndex,3));
    metrics.MaxMach = metrics.MaxVelocityFtS / cfg.soundSpeedFtS;
    metrics.MaxAccelerationFtS2 = max(vehicle(1:apogeeIndex,4));
    metrics.MaxNetG = metrics.MaxAccelerationFtS2 / g;
    metrics.AverageThrustToWeight = motor.AverageThrustLbf / totalLbm;
    metrics.PeakThrustToWeight = motor.PeakThrustLbf / totalLbm;
    metrics.VehicleFlightTimeS = vehicle(end,1);
    metrics.VehicleDescentTimeS = vehicle(end,1) - apogeeTime;
    metrics.VehicleImpactVelocityFtS = abs(vehicle(end,3));
    metrics.PayloadFlightTimeS = NaN;
    metrics.PayloadDescentTimeS = NaN;
    metrics.PayloadImpactVelocityFtS = NaN;
    metrics.PayloadReleaseTimeS = NaN;
    if deploying
        metrics.PayloadFlightTimeS = payload(end,1);
        metrics.PayloadDescentTimeS = payload(end,1) - apogeeTime;
        metrics.PayloadImpactVelocityFtS = abs(payload(end,3));
        metrics.PayloadReleaseTimeS = payloadStart(1);
    end
    metrics.DrogueTerminalEstimateFtS = vtDrogue;
    metrics.MainFullyOpenEstimateFt = mainOpenAltitude;
    flight.Mode = mode;
    flight.Recovery = recovery;
    flight.LaunchAngleDeg = angleDeg;
    flight.Vehicle = vehicle;
    flight.Payload = payload;
    flight.Events = events;
    flight.Metrics = metrics;
    flight.PhaseNames = {'Powered ascent','Coast','Before drogue opens', ...
        'Drogue descent','Main descent','Main after payload release', ...
        'Payload free fall','Payload chute descent'};

    function force = dragForce(cdArea, altitude, velocity)
        rho = slvtDensity(altitude + cfg.siteAltitudeFt, cfg.atmosphere);
        force = -0.5 * rho * cdArea * velocity * abs(velocity);
    end

    function step = timeToAltitude(target, acceleration, limit)
        predicted = h + v * limit + 0.5 * acceleration * limit^2;
        step = limit;
        if predicted <= target
            step = crossingTime(h, v, acceleration, target, limit);
        end
    end

    function advanceVehicle(step, acceleration, code, padHold)
        oldH = h; oldV = v; oldT = t;
        if ~padHold && h + v * step + 0.5 * acceleration * step^2 < 0
            step = crossingTime(h, v, acceleration, 0, step);
        end
        h = h + v * step + 0.5 * acceleration * step^2;
        v = v + acceleration * step; t = t + step;
        if padHold && h < 0
            h = 0; v = 0; acceleration = 0;
        else
            h = max(h, 0);
            if code >= 3 && h < 1e-8, h = 0; end
        end
        if code >= 3
            assert(v <= 1e-6, 'SLVT:StepSize', 'Vehicle integration became unstable. Reduce time step.');
        end
        if isnan(railTime) && oldH < cfg.railLengthFt && h >= cfg.railLengthFt && code <= 2
            tau = crossingTime(oldH, oldV, acceleration, cfg.railLengthFt, step);
            railTime = oldT + tau; railVelocity = oldV + acceleration * tau;
            addEvent('Effective rail exit', 'Vehicle', railTime, cfg.railLengthFt, railVelocity);
        end
        n = n + 1;
        if n > size(vehicle,1), vehicle(end+capacity,6) = 0; end
        vehicle(n,:) = [t h v acceleration mass*g code];
        checkRun(t, n);
    end

    function checkRun(time, index)
        assert(time <= cfg.maxTimeS + 1e-8, 'SLVT:Timeout', ...
            'No touchdown within %.0f seconds. Check inputs or increase maximum time.', cfg.maxTimeS);
        assert(isfinite(time) && isfinite(h) && isfinite(v), 'SLVT:Numerics', 'Nonfinite flight state.');
        if mod(index, 2000) == 0 && cancelCheck()
            error('SLVT:Cancelled', 'Run cancelled. Previous results are retained.');
        end
    end

    function addEvent(name, body, time, altitude, velocity)
        events(end+1) = struct('Name',name,'Body',body,'TimeS',time, ...
            'AltitudeFt',altitude,'VelocityFtS',velocity);
    end
end

function tau = crossingTime(h, v, a, target, limit)
% Solve the same constant-acceleration position equation at an event.
    if abs(a) < 1e-12
        tau = (target - h) / v;
    else
        discriminant = max(0, v*v + 2*a*(target-h));
        direction = 1;
        if v < 0, direction = -1; end
        q = -0.5*(v + direction*sqrt(discriminant));
        roots = [2*q/a, (h-target)/q]; % stable quadratic roots near touchdown
        roots = roots(roots >= -1e-9 & roots <= limit + 1e-8);
        assert(~isempty(roots), 'SLVT:Numerics', 'Could not locate a flight event.');
        tau = max(roots);
    end
    tau = min(limit, max(0, tau));
end
