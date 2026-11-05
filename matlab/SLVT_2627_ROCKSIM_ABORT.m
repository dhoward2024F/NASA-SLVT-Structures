%% MATLAB Simulation for Launch Vehicle Flight and Payload Retainment
% Designed for 2027 Fullscale Vehicle
% Based on script by Benjamin Putka
% Author: David Howard
% For use by NASA SLVT
% Version: 10/10/2026

clear, clc, close all



%% NOTES
% Purpose: Predicts mission performance by iteratively calculating flight
% characteristics using dead reckoning.

% All calculations are done in imperial units.
% Pressure is based on the 1976 Standard Atmosphere.
% Define x-y axes system as horizontal and vertical axes.

% ASSUMPTIONS: 
%   Constant acceleration due to gravity
%   Starting position at ground level
%   Motor propellant burns at a constant rate
%   Constant angle of ascent corresponding to the launch angle
%   Constant coefficient of drag for launch vehicle during ascent
%   Negligible drag for launch vehicle during descent
%   Wind acts in the horizontal direction
%   Drift radius is zero at apogee
%   No lateral force on vehicle during descent besides wind

% ORDER OF OPERATIONS
% Initialize -> propagate -> update -> correct
% 1. Define variables describing launch vehicle, setup, and environment
% 2. Simulate flight using multiple loops for different launch segments
%       1st loop: launch to motor burnout
%       2nd loop: motor burnout to apogee
%       3rd loop: apogee to drogue deployment
%       4th loop: drogue deployment to main deployment
%       5th loop: main deployment to ground impact of VEHICLE
% 3. Final calculations
% 4. Plot results

% REQUIRES atmos.m in your file directory for calculating density at
% altitude
% REQUIRES plotORdata.m in your file directory IF plotting results


%% VARIABLES TO SPECIFY EACH SIMULATION

launchAngle = 5; % launch angle, in degrees
recovery = 1; % recovery system (primary = 1, secondary = 2, tertiary = 3)
alt = 800; % launch site altitude above sea level, in ft [Braggs Farms]


%% CONSTANTS

% --- Environment constants ---
g = 32.174; % gravitational acceleration (ft/s^2)
c = 1125.33; % speed of sound [dry air at 68 deg F] (ft/s)

% Wind speeds
WIND0  = 0;                % 0 mph windspeed
WIND5  = 5  * 5280 / 3600; % 5 mph windspeed in ft/s
WIND10 = 10 * 5280 / 3600; % 10 mph windspeed in ft/s
WIND15 = 15 * 5280 / 3600; % 15 mph windspeed in ft/s
WIND20 = 20 * 5280 / 3600; % 20 mph windspeed in ft/s

% --- Vehicle constants ---
MASS_TOTAL   = 881   / (16*g);    % total vehicle mass, including motor (slugs)
MASS_FORWARD = 261.5 / (16*g);    % forward section mass (slugs)
MASS_CENTRAL = 235   / (16*g);    % central section mass (slugs)
MASS_AFT     = 363   / (16*g);    % aft section mass (slugs)
MASS_PROP    = 2518  / (453.6*g); % motor propellant mass (slugs) [L2200]

DIAMETER_BODY = 6.17 / 12; % diameter of launch vehicle (ft)
A_NOSECONE = pi * DIAMETER_BODY^2 / 4; % cross sectional area of nose cone (ft^2)
H_FINS = 6 / 12; % height of fins (ft)
T_FINS = 0.25 / 12; % thickness of fins (ft)
A_FINS = 4 * H_FINS * T_FINS; % top surface area of all four fins
CD_BODY = 0.515; % coefficient of drag for the launch vehicle
    % CD_BODY is calculated through CFD analysis of launch vehicle CAD

RAIL_LENGTH_EFF = (144 - 29) / 12; % effective launch rail length (ft)
THETA = deg2rad(launchAngle); % launch angle, in radians

% --- Parachute constants ---
if recovery == 1
    % Primary recovery:
    DROGUE_DEP_TIME = 0; % time after apogee till drogue deployment (s)
    MAIN_DEP_ALT = 625;  % team specified altitude of main deployment (ft AGL)
elseif recovery == 2
    % Secondary recovery:
    DROGUE_DEP_TIME = 1; % time after apogee till drogue deployment (s)
    MAIN_DEP_ALT = 525;  % team specified altitude of main deployment (ft AGL)
elseif recovery == 3
    % Tertiary recovery:
    DROGUE_DEP_TIME = 2; % time after apogee till drogue deployment (s)
    MAIN_DEP_ALT = 500;  % team specified altitude of main deployment (ft AGL)
else
    disp("Error: Invalid recovery system specified")
    return
end

OPEN_TIME_MAIN = 1.25;  % time for main parachute to fully open
OPEN_TIME_DROGUE = 0.1; % time for drogue parachute to fully open
    % The above is verified through bridge testing

CD_DROGUE = 0.970; % coefficient of drag for drogue parachute
CD_MAIN = 2.2;     % coefficient of drag for main parachute

DIAMETER_DROGUE = 2; % diameter of drogue parachute (ft)
DIAMETER_MAIN = 14;  % diameter of main parachute (ft)

A_DROGUE = pi * DIAMETER_DROGUE^2 / 4; % area of drogue parachute (ft^2)
A_MAIN = pi * DIAMETER_MAIN^2 / 4;     % area of main parachute (ft^2)

MASS_DROGUE = 26.8 / (16*g); % mass of drogue recovery hardware (slugs)
MASS_MAIN   = 52.5 / (16*g); % mass of main recovery hardware (slugs)
    % "Recovery hardware:" parachute, shock cord, quick links, flame shield


%% Define vectors and known data

% Known data from csv file from thrust curve for AeroTech L2200G motor
% Credit to Christopher Kobel for data
motorData = readmatrix('AeroTech_L2200G.csv', 'NumHeaderLines', 5);
time_steps_motor = motorData(:,1);
thrust_steps_motor = motorData(:,2) * 0.2248089431; % N to lbf
% Establish zero thrust at ignition if the curve starts after t = 0.
if time_steps_motor(1) > 0
    time_steps_motor = [0; time_steps_motor];
    thrust_steps_motor = [0; thrust_steps_motor];
end
burnTime = time_steps_motor(end);

% Define vectors to store the vertical flight simulation data
tv = NaN(1,100000); % time (sec)
sv = NaN(1,100000); % vertical position, from ground (ft)
vv = NaN(1,100000); % velociy (ft/s)
av = NaN(1,100000); % acceleration (ft/s^2)

% Define vectors to measure drift radius 
drift_v0  = NaN(1,100000); % Vector to measure drift radius at 0 mph winds
drift_v5  = NaN(1,100000); % Vector to measure drift radius at 5 mph winds
drift_v10 = NaN(1,100000); % Vector to measure drift radius at 10 mph winds
drift_v15 = NaN(1,100000); % Vector to measure drift radius at 15 mph winds
drift_v20 = NaN(1,100000); % Vector to measure drift radius at 20 mph winds


%% Initialize looping variables

t_step = 0.001; % time step for simulation (sec)
s0 = 0; % Initial vertical position (ft)
v0 = 0; % Initial vertical velocity (ft/s)
s = 0; % Final vertical position (ft)
v = inf; % Final vertical velocity (ft/s)

% Variables that update after each loop
Mass_Vehicle = MASS_TOTAL; % total mass of the vehicle at stage of flight
Gravity_Force = Mass_Vehicle * -g; % gravitational force on the vehicle


%% 1st loop: launch to motor burnout

i = 1; % Looping variable for the vehicle

% ASSUME propellant mass burns at a constant rate
burnRate = MASS_PROP / (burnTime / t_step); % mass of propellant burned in a single time step

r = 2; % looping variable to track time till rail exit

% Loop until burnout
while ((i * t_step) <= burnTime)
    % Retrieve thrust interpolated from imported thrust steps and time steps
    Thrust = interpolate_thrust(time_steps_motor, thrust_steps_motor, i);
    
    % Calculate drag of vehicle using area of nose cone and top of fins
    Body_Drag = -calc_drag(CD_BODY, (A_NOSECONE + A_FINS), v0, s0+alt);
    
    % Calculate new position data
    Fy_Total = (Thrust + Body_Drag) * cos(THETA) + Gravity_Force;
    [a, v, s] = calc_kinematics(Fy_Total, Mass_Vehicle, s0, v0, t_step);
    
    % Make sure launch vehicle is not going below ground
    if (s < 0)
        a = 0;
        v = 0;
        s = 0;
    end

    % Check if launch vehicle has not left the rail
    if (s <= RAIL_LENGTH_EFF)
        r = r + 1;
    end

    % Reassign variables
    s0 = s;
    v0 = v;

    % Update simulation data vectors for vehicle
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;

    % Update vehicle mass and force of gravity
    Mass_Vehicle = Mass_Vehicle - burnRate; % new vehicle mass
    Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass
    
    % fprintf("T = %8.3f | D = %8.3f | G = %8.3f | Fy = %8.3f | a = %8.3f | v = %8.3f | s = %8.3f | t = %8.3f\n", ...
    %     Thrust, Body_Drag, Gravity_Force, Fy_Total, a, v, s, tv(i)); % uncomment for debugging

    % Update looping variable
    i = i + 1;
end
fprintf('Loop 1 complete: i = %d, t = %g, h = %g, \tFlight Event: BURNOUT\n', ...
    i-1, tv(i-1), sv(i-1));

% Update vehicle mass and force of gravity
Mass_Vehicle = MASS_TOTAL - MASS_PROP; % make sure all propellant mass is subtracted
Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass

RailExit_V = vv(r); % retrieve velocity at rail exit (ft/s)


%% 2nd loop: motor burnout to apogee

% Loop until vertical velocity is 0
while (v >= 0)
    % Calculate drag of vehicle using area of nose cone and top of fins
    Body_Drag = -calc_drag(CD_BODY, (A_NOSECONE + A_FINS), v0, s0+alt);

    % Calculate new position data
    Fy_Total = Body_Drag * cos(THETA) + Gravity_Force;
    [a, v, s] = calc_kinematics(Fy_Total, Mass_Vehicle, s0, v0, t_step);
    
    % Reassign variables
    s0 = s;
    v0 = v;

    % Update simulation data vectors for vehicle
    tv(i) = i * t_step; % add on top of motor burn time
    sv(i) = s;
    vv(i) = v;
    av(i) = a;

    % Update looping variable
    i = i + 1;
end
fprintf('Loop 2 complete: i = %d, t = %g, h = %g, \tFlight Event: APOGEE\n', ...
    i-1, tv(i-1), sv(i-1));

% Save apogee info
apogee = sv(i-1); % apogee (ft)
time2Apogee = tv(i-1); % time to apogee (s)
apogee_idx = i-1;


%% 3rd loop: apogee to drogue deployment

descentTime = 0; % variable to track descent time (s)
k = 0; % variable to track time steps since apogee

% Drogue takes about 0.5 seconds to open
while (descentTime <= DROGUE_DEP_TIME + OPEN_TIME_DROGUE)
    % Calculate new position data
    Fy_Total = Gravity_Force;
    [a, v, s] = calc_kinematics(Fy_Total, Mass_Vehicle, s0, v0, t_step);
    
    % Reassign variables
    s0 = s;
    v0 = v;
    descentTime = descentTime + t_step;

    % Update simulation data vectors for vehicle
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;

    % Update drift radius vectors
    drift_v0(i)  = WIND0  * t_step * k;
    drift_v5(i)  = WIND5  * t_step * k;
    drift_v10(i) = WIND10 * t_step * k;
    drift_v15(i) = WIND15 * t_step * k;
    drift_v20(i) = WIND20 * t_step * k;

    % Update looping variables
    i = i + 1;
    k = k + 1;
end
fprintf('Loop 3 complete: i = %d, t = %g, h = %g, \tFlight Event: DROGUE DEPLOYMENT\n', ...
    i-1, tv(i-1), sv(i-1));

% Update vehicle mass and force of gravity
Mass_Vehicle = Mass_Vehicle - MASS_DROGUE; % vehicle mass without drogue mass
Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass


%% 4th loop: drogue deployment to main deployment

% After main deployment occcurs, it takes 1.5 seconds * terminal
% velocity under drogue to fully deploy

% Terminal velocity of vehicle under drogue
vt_drogue = sqrt((2 * Mass_Vehicle * g) / (atmos(sv(i-1), 'units', 'US') ...
    * A_DROGUE * CD_DROGUE));

% Vertical height at which main is fully deployed
s_MainDeployed = MAIN_DEP_ALT - OPEN_TIME_MAIN * vt_drogue;

% Loop until height at which main is fully deployed
while (s >= s_MainDeployed)
    % Calculate drag generated from drogue
    Drogue_Drag = calc_drag(CD_DROGUE, A_DROGUE, v0, s0+alt);
    
    % Calculate new position data
    Fy_Total = Drogue_Drag + Gravity_Force;
    [a, v, s] = calc_kinematics(Fy_Total, Mass_Vehicle, s0, v0, t_step);
    
    % Reassign variables
    s0 = s;
    v0 = v;
    descentTime = descentTime + t_step;

    % Update simulation data vectors for vehicle
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;

    % Update drift radius vectors
    drift_v0(i)  = WIND0  * t_step * k;
    drift_v5(i)  = WIND5  * t_step * k;
    drift_v10(i) = WIND10 * t_step * k;
    drift_v15(i) = WIND15 * t_step * k;
    drift_v20(i) = WIND20 * t_step * k;

    % Update looping variables
    i = i + 1;
    k = k + 1;
end
fprintf('Loop 4 complete: i = %d, t = %g, h = %g, \tFlight Event: MAIN DEPLOYMENT\n', ...
    i-1, tv(i-1), sv(i-1));

% Update vehicle mass and force of gravity
Mass_Vehicle = Mass_Vehicle - MASS_MAIN; % vehicle mass without main mass
Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass


%% 5th loop: main deployment to ground impact

% Loop till AGL = 0
while (s >= 0)
    % Calculate drag generated from drogue
    Drogue_Drag = calc_drag(CD_DROGUE, A_DROGUE, v0, s0+alt);

    % Calculate drag generated from main
    Main_Drag = calc_drag(CD_MAIN, A_MAIN, v0, s0+alt);

    % Calculate new position data
    Fy_Total = Drogue_Drag + Main_Drag + Gravity_Force;
    [a, v, s] = calc_kinematics(Fy_Total, Mass_Vehicle, s0, v0, t_step);
    
    % Reassign variables
    s0 = s;
    v0 = v;
    descentTime = descentTime + t_step;

    % Update simulation data vectors for vehicle
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;

    % Update drift radius vectors
    drift_v0(i)  = WIND0  * t_step * k;
    drift_v5(i)  = WIND5  * t_step * k;
    drift_v10(i) = WIND10 * t_step * k;
    drift_v15(i) = WIND15 * t_step * k;
    drift_v20(i) = WIND20 * t_step * k;

    % Update looping variables
    i = i + 1;
    k = k + 1;
end

% Update looping variables so last index will be last recorded position
i = i - 1;
k = k - 1;

% Set position data to zero if last altitude measurement was negative
if (s < 0)
    sv(i) = 0;
end

fprintf('Loop 5 complete: i = %d, t = %g, h = %g, \t\tFlight Event: VEHICLE TOUCHDOWN\n', ...
    i, tv(i), sv(i));


%% Final Calculations

% Retrieve mass of each section on landing
Mass_For_Landing = MASS_FORWARD;
Mass_Cen_Landing = MASS_CENTRAL - MASS_MAIN;
Mass_Aft_Landing = MASS_AFT - MASS_PROP - MASS_DROGUE;

% Retrieve ground impact velocities
Final_Velocity_Vehicle = abs(vv(i)); % velocity of vehicle at ground impact (ft/s)

% Calculate Kinetic Energy of each section at ground impact in ft-lbf
forKE = 0.5 * Mass_For_Landing * Final_Velocity_Vehicle^2;
cenKE = 0.5 * Mass_Cen_Landing * Final_Velocity_Vehicle^2;
aftKE = 0.5 * Mass_Aft_Landing * Final_Velocity_Vehicle^2;

% Calculate Kinetic Energy of each section under drogue in ft-lbf
forKE_d = 0.5 * (MASS_FORWARD + MASS_CENTRAL) * vt_drogue^2;
aftKE_d = 0.5 * (MASS_AFT - MASS_PROP - MASS_DROGUE) * vt_drogue^2;

% Calculate certain overall performance characteristics
totalTime = tv(i); % Total flight time (s)
maxV = max(vv(1:apogee_idx)); % Maximum velocity during flight (ft/s)
maxM = maxV / c; % Maximum Mach number during flight (Mach)
maxA = max(av(1:apogee_idx)); % Maximum acceleration experienced by launch vehicle during flight (ft/s^2)
maxG = maxA / g; % Maximum G-loading (G's)

% Format certain results for display in tables
performanceTable = table(["Apogee (ft)"; "Descent Time"; ...
    "Rail Exit Velocity (ft/s)"; "Maximum Mach Number"; ...
    "Maximum Velocity (ft/s)"; "Maximum Acceleration (ft/s^2)"; "Maximum G-loading [G]"], ...
    [apogee; descentTime; RailExit_V; maxM; maxV; maxA; maxG], ...
    'VariableNames', {'Performance Parameter', 'Result'});

sectionLabels = ["Forward Section"; "Central Section"; "Aft Section"];
KETable = table(sectionLabels, ...
    [Mass_For_Landing * g; Mass_Cen_Landing * g; Mass_Aft_Landing * g], ...
    [Final_Velocity_Vehicle; Final_Velocity_Vehicle; Final_Velocity_Vehicle], ...
    [forKE; cenKE; aftKE], 'VariableNames', {'Section', 'Mass (lbs)', 'Impact Velocity (ft/s)', 'Kinetic Energy (ft-lbf)'});

driftTable = table([0; 5; 10; 15; 20], ...
    [drift_v0(i); drift_v5(i); drift_v10(i); drift_v15(i); drift_v20(i)], ...
    'VariableNames', {'Wind Speed (mph)', 'Drift Radius (ft)'});

flightProfileTable = table(sectionLabels, ...
    [MASS_FORWARD * g; MASS_CENTRAL * g; MASS_AFT * g], ...
    [MASS_FORWARD * g; MASS_CENTRAL * g; (MASS_AFT-MASS_PROP) * g], ...
    [Mass_For_Landing * g; Mass_Cen_Landing * g; Mass_Aft_Landing * g], ...
    [vt_drogue; vt_drogue; vt_drogue], ...
    [forKE_d; forKE_d; aftKE_d], ...
    [Final_Velocity_Vehicle; Final_Velocity_Vehicle; Final_Velocity_Vehicle], ...
    [forKE; cenKE; aftKE], 'VariableNames', ...
    {'Section', 'Lift-off Mass [lbm]', 'Burnout Mass [lbm]', 'Landing Mass [lbm]', 'Drogue Descent Rate [ft/s]', ...
        'Kinetic Energy under Drogue [ft-lbf]', 'Main Descent Rate [ft/s]', 'Kinetic Energy under Main [ft-lbf]'});


%% Display key information

fprintf('\n\nFlight simulation values for a launch angle of %d degrees:\n\n',...
    launchAngle);

fprintf('Apogee: %.2f ft \n', apogee);
fprintf('Time to apogee: %.2f sec \n\n', time2Apogee);

fprintf('Descent time of vehicle: %.2f sec \n', descentTime);
fprintf('Total flight time of vehicle: %.2f sec \n', totalTime);

fprintf('Impact velocity of vehicle: %.2f ft/sec \n\n', ...
    Final_Velocity_Vehicle);

disp(performanceTable)
disp(KETable)
disp(driftTable)
disp(flightProfileTable)


%% Plot results

% Set default plot settings
set(groot,'defaultfigurecolor','w');
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultTextInterpreter','latex');
set(groot,'defaultLegendInterpreter','latex');
set(groot,'defaultAxesTickLabelInterpreter','latex');
set(groot,'defaultAxesFontSize',16);
set(groot,'defaultLineLineWidth',2);

% Plot the flight simulation vectors for the vehicle 
plotORdata(sv,vv,av,tv)
title('MATLAB Flight Profile of $Venture$')



%% FUNCTIONS

function thrust_at_index = interpolate_thrust(time_steps, thrust_steps, i)
% INTERPOLATE_THRUST Returns interpolated thrust at a given index.
%
%   thrust_at_index = interpolate_thrust_at_index(time_steps, thrust_steps, i)
%
% Inputs:
%   time_steps   - Vector of time points (s) where thrust is known
%   thrust_steps - Vector of thrust values (N) corresponding to each time step
%   i            - Time step index
%
% Output:
%   thrust_at_index - Thrust (lbf) at that interpolated time

    % Ensure column vectors
    time_steps = time_steps(:);
    thrust_steps = thrust_steps(:);

    % Define uniform time vector (0.001 s step)
    t_interp = (time_steps(1):0.001:time_steps(end))';

    % Perform linear interpolation
    thrust_interp = interp1(time_steps, thrust_steps, t_interp, 'linear');

    % Check for valid index
    if i < 1 || i > length(thrust_interp)
        error('Index %d is out of range. Valid range: 1 to %d', i, length(thrust_interp));
    end

    % Return thrust at that index
    thrust_at_index = thrust_interp(i);
end


function [D] = calc_drag(CD, A, V, h)
% CALC_DRAG returns drag calculated using inputed parameters.
% 
% Inputs:
%   CD - coefficient of drag
%   A  - surface area
%   V  - velocity
%   h  - altitude above sea level
% 
% Output:
%   D - calculated force of drag
    
    rho = atmos(h, 'units', 'US'); % retrieve density at altitude (slugs/ft^3)
    D = 0.5 * CD * A * rho * V^2;
end


function [a, v, s] = calc_kinematics(F, M, s0, v0, t_Step)
% CALC_KINEMATICS returns new acceleration, velocity, and position from 
% an initial position after a given time step using Newton's second law  
% and kinematics.
% 
% Inputs:
%   F      - total force acting on body
%   M      - total mass
%   s0     - initial position
%   v0     - initial velocity
%   t_Step - time step
% 
% Returns:
%   a - new acceleration
%   v - new velocity
%   s - new position
    
    a = F / M; % calculate acceleration (ft/s^2)
    v = v0 + a * t_Step; % calculate new velocity (ft/s)
    s = t_Step * (v + v0) / 2 + s0; % new position (ft)
end