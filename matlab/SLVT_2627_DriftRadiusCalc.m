%% Drift Radius Calculation from OpenRocket Simulation Results
% Author: David Howard
% For use by NASA SLVT
% Version: 10/28/2026

clear, clc, close all


%% Fill in OpenRocket simulation result values

% 10 deg launch angle results, mph: [0 5 10 15 20]
FlightTime =  [ 114  110  109  110  109]'; % in seconds
Time2Apogee = [17.1 16.9 16.8 16.6 16.4]'; % in seconds


%% Calculate drift radius
% Distance = WindSpeed * DescentTime

% Wind speeds
WIND0  = 0;                % 0 mph windspeed
WIND5  = 5  * 5280 / 3600; % 5 mph windspeed in ft/s
WIND10 = 10 * 5280 / 3600; % 10 mph windspeed in ft/s
WIND15 = 15 * 5280 / 3600; % 15 mph windspeed in ft/s
WIND20 = 20 * 5280 / 3600; % 20 mph windspeed in ft/s

WindSpeed = [WIND0 WIND5 WIND10 WIND15 WIND20]';

DescentTime = FlightTime - Time2Apogee

DriftRadius = WindSpeed .* DescentTime;


%% Display the results

results = table([0;5;10;15;20], ...
    [DriftRadius(1,1); DriftRadius(2,1); DriftRadius(3,1); ...
        DriftRadius(4,1); DriftRadius(5,1)], ...
    'VariableNames', {'Wind Speed [mph]'; ...
        'Drift Radius for 10 Deg [ft]'});
disp(results);