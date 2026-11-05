%% MATLAB Simulation for Launch Vehicle Flight and Payload Deployment
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
%       5th loop: main deployment to payload deployment
%       6th loop: payload deployment to ground impact of VEHICLE
%       7th loop: payload deployment to payload parachute opening
%       8th loop: payload chute opening to ground impact of PAYLOAD
% 3. Final calculations
% 4. Plot results

% REQUIRES atmos.m in your file directory for calculating density at
% altitude
% REQUIRES plotORdata.m in your file directory IF plotting results


%% VARIABLES TO SPECIFY EACH SIMULATION

launchAngle = 10; % launch angle, in degrees
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
MASS_TOTAL   = 56.1875   / (g);    % total vehicle mass, including motor (slugs)
MASS_PAYLOAD = 12.43 / (g);    % deployable mass; payload and nosecone (slugs)
MASS_FORWARD = 5.73  / (g);    % forward section mass (slugs)
MASS_CENTRAL = 14.7   / (g);    % central section mass (slugs)
MASS_AFT     = 22.69   / (g);    % aft section mass (slugs)
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
PAYLOAD_DEP_ALT = 300; % team specified altitude of payload deployment (ft AGL)

OPEN_TIME_MAIN = 1.25;       % time for main parachute to fully open
OPEN_TIME_DROGUE = 0.1;      % time for drogue parachute to fully open
OPEN_TIME_PAYLOAD_CHUTE = 1; % time for payload parachute to fully open
    % The above is verified through bridge testing

CD_DROGUE = 0.97;         % coefficient of drag for drogue parachute
CD_MAIN = 2.2;            % coefficient of drag for main parachute
CD_PAYLOAD_CHUTE = 1.122; % coefficient of drag for payload parachute

DIAMETER_DROGUE = 2;        % diameter of drogue parachute (ft)
DIAMETER_MAIN = 14;         % diameter of main parachute (ft)
DIAMETER_PAYLOAD_CHUTE = 6; % diameter of payload parachute (ft)

A_DROGUE = pi * DIAMETER_DROGUE^2 / 4; % area of drogue parachute (ft^2)
A_MAIN = pi * DIAMETER_MAIN^2 / 4; % area of main parachute (ft^2)
A_PAYLOAD_CHUTE = pi * DIAMETER_PAYLOAD_CHUTE^2 / 4; % area of payload parachute (ft^2)

MASS_DROGUE        = 26.8 / (16*g); % mass of drogue recovery hardware (slugs)
MASS_MAIN          = 52.5 / (16*g); % mass of main recovery hardware (slugs)
MASS_PAYLOAD_CHUTE = 10.9 / (16*g); % mass of payload recovery hardware (slugs)
    % "Recovery hardware:" parachute, shock cord, quick links, flame shield


%% Define vectors and known data

% Known data from csv file from thrust curve for AeroTech L2200G motor
% Credit to Christopher Kobel for data
% motorData = readtable('AeroTech_L2200G.csv');
% time_steps_motor = table2array(motorData(:,1)); % extract time steps
% thrust_steps_motor = table2array(motorData(:,2)); % extract thrust steps
time_steps_motor = [0.011; 0.024; 0.037; 0.05; 0.1; 0.15; 0.2; 0.25; ...
    0.3; 0.35; 0.4; 0.5; 0.6; 0.7; 0.8; 0.9; 1; 1.1; 1.186; 1.227; ...
    1.27; 1.3; 1.4; 1.5; 1.6; 1.7; 1.8; 1.9; 2; 2.048; 2.084; 2.102; ...
    2.134; 2.186; 2.237; 2.3; 2.4];
thrust_steps_motor = [1195.177; 2029.903; 2380.868; 2542.122; 2570.578; ...
    2561.093; 2523.151; 2485.208; 2523.151; 2570.578; 2674.919; ...
    2912.057; 3073.311; 3073.311; 3101.768; 3092.282; 3092.282; ...
    2959.485; 2807.716; 2437.781; 2257.556; 2162.701; 1991.961; ...
    1878.135; 1792.765; 1688.424; 1612.540; 1584.083; 1536.656; ...
    1498.714; 1403.858; 1166.72; 796.784; 455.305; 237.138; 94.855; 0]; % in Newtons

thrust_steps_motor = thrust_steps_motor .* 0.2248089431; % convert N to lbf
burnTime = time_steps_motor(length(time_steps_motor));

% Establish zero thrust at ignition if the curve starts after t = 0.
if time_steps_motor(1) > 0
    time_steps_motor = [0; time_steps_motor];
    thrust_steps_motor = [0; thrust_steps_motor];
end

% Define vectors to store the vertical flight simulation data
tv = NaN(1,100000); % time (sec)
sv = NaN(1,100000); % vertical position, from ground (ft)
vv = NaN(1,100000); % velociy (ft/s)
av = NaN(1,100000); % acceleration (ft/s^2)
% same vectors for payload
tpv = NaN(1,100000);
spv = NaN(1,100000); 
vpv = NaN(1,100000);
apv = NaN(1,100000);

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

i = 1; % Looping variable for the VEHICLE
j = 1; % Looping variable for the PAYLOAD

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

    % Update simulation data vectors for both vehicle and payload
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;
    tpv(j) = j * t_step;
    spv(j) = s;
    vpv(j) = v;
    apv(j) = a;

    % Update vehicle mass and force of gravity
    Mass_Vehicle = Mass_Vehicle - burnRate; % new vehicle mass
    Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass
    
    % fprintf("T = %8.3f | D = %8.3f | G = %8.3f | Fy = %8.3f | a = %8.3f | v = %8.3f | s = %8.3f | t = %8.3f\n", ...
    %     Thrust, Body_Drag, Gravity_Force, Fy_Total, a, v, s, tv(i)); % uncomment for debugging

    % Update looping variables
    i = i + 1;
    j = j + 1;
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

    % Update simulation data vectors for both vehicle and payload
    tv(i) = i * t_step; % add on top of motor burn time
    sv(i) = s;
    vv(i) = v;
    av(i) = a;
    tpv(j) = j * t_step; % add on top of motor burn time
    spv(j) = s;
    vpv(j) = v;
    apv(j) = a;

    % fprintf("D = %8.3f | G = %8.3f | Fy = %8.3f | a = %8.3f | v = %8.3f | s = %8.3f | t = %8.3f\n", ...
    %     Body_Drag, Gravity_Force, Fy_Total, a, v, s, tv(i)); % uncomment for debugging

    % Update looping variables
    i = i + 1;
    j = j + 1;
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

% Loop until drogue is fully open
while (descentTime <= DROGUE_DEP_TIME + OPEN_TIME_DROGUE)
    % Calculate new position data
    Fy_Total = Gravity_Force;
    [a, v, s] = calc_kinematics(Fy_Total, Mass_Vehicle, s0, v0, t_step);
    
    % Reassign variables
    s0 = s;
    v0 = v;
    descentTime = descentTime + t_step;

    % Update simulation data vectors for both vehicle and payload
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;
    tpv(j) = j * t_step;
    spv(j) = s;
    vpv(j) = v;
    apv(j) = a;

    % Update drift radius vectors
    drift_v0(i)  = WIND0  * t_step * k;
    drift_v5(i)  = WIND5  * t_step * k;
    drift_v10(i) = WIND10 * t_step * k;
    drift_v15(i) = WIND15 * t_step * k;
    drift_v20(i) = WIND20 * t_step * k;

    % Update looping variables
    i = i + 1;
    j = j + 1;
    k = k + 1;
end
fprintf('Loop 3 complete: i = %d, t = %g, h = %g, \tFlight Event: DROGUE DEPLOYMENT\n', ...
    i-1, tv(i-1), sv(i-1));

% Update vehicle mass and force of gravity
Mass_Vehicle = Mass_Vehicle - MASS_DROGUE; % vehicle mass without drogue mass
Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass


%% 4th loop: drogue deployment to main deployment

% After main deployment occcurs, it takes about 2.5 seconds * terminal
% velocity under drogue to fully deploy

% Terminal velocity of vehicle under drogue
vt_drogue = sqrt((2 * Mass_Vehicle * g) / (atmos(sv(i-1), 'units', 'US')...
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

    % Update simulation data vectors for both vehicle and payload
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;
    tpv(j) = j * t_step;
    spv(j) = s;
    vpv(j) = v;
    apv(j) = a;

    % Update drift radius vectors
    drift_v0(i)  = WIND0  * t_step * k;
    drift_v5(i)  = WIND5  * t_step * k;
    drift_v10(i) = WIND10 * t_step * k;
    drift_v15(i) = WIND15 * t_step * k;
    drift_v20(i) = WIND20 * t_step * k;

    % Update looping variables
    i = i + 1;
    j = j + 1;
    k = k + 1;
end
fprintf('Loop 4 complete: i = %d, t = %g, h = %g, \tFlight Event: MAIN DEPLOYMENT\n', ...
    i-1, tv(i-1), sv(i-1));

% Update vehicle mass and force of gravity
Mass_Vehicle = Mass_Vehicle - MASS_MAIN; % vehicle mass without main mass
Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass


%% 5th loop: main deployment to payload deployment

% Loop till altitude of payload deployment
while (s >= PAYLOAD_DEP_ALT)
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

    % Update simulation data vectors for both vehicle and payload
    tv(i) = i * t_step;
    sv(i) = s;
    vv(i) = v;
    av(i) = a;
    tpv(j) = j * t_step;
    spv(j) = s;
    vpv(j) = v;
    apv(j) = a;

    % Update drift radius vectors
    drift_v0(i)  = WIND0  * t_step * k;
    drift_v5(i)  = WIND5  * t_step * k;
    drift_v10(i) = WIND10 * t_step * k;
    drift_v15(i) = WIND15 * t_step * k;
    drift_v20(i) = WIND20 * t_step * k;

    % Update looping variables
    i = i + 1;
    j = j + 1;
    k = k + 1;
end
fprintf('Loop 5 complete: i = %d, t = %g, h = %g, \tFlight Event: PAYLOAD DEPLOYMENT\n', ...
    i-1, tv(i-1), sv(i-1));

% Update vehicle mass and force of gravity
Mass_Vehicle = Mass_Vehicle - MASS_PAYLOAD; % vehicle mass without payload/forward section mass
Gravity_Force = Mass_Vehicle * -g; % force of gravity with new mass

% Initialize new variables to track payload
sp0 = sv(i-1); % initial vertical altitude of payload (ft)
vp0 = vv(i-1); % initial velocity of payload (ft/s)
ap0 = av(i-1); % initial acceleration of payload (ft/s^2)
sp = sp0; % final vertical altitude of payload (ft)
vp = vp0; % final velocity of payload (ft/s)
driftp_v0  = drift_v0;
driftp_v5  = drift_v5;
driftp_v10 = drift_v10;
driftp_v15 = drift_v15;
driftp_v20 = drift_v20;


%% 6th loop: payload deployment to ground impact OF VEHICLE

% Loop until vertical position is 0
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

fprintf('Loop 6 complete: i = %d, t = %g, h = %g, \t\tFlight Event: VEHICLE TOUCHDOWN\n', ...
    i, tv(i), sv(i));


%% 7th loop: payload deployment to full payload parachute deployment

% Initialize new variables to track payload descent time
timePayloadDeployment = tpv(j-1); % store time at payload chute deployment
descentTimePayloadDep = 0; % payload descent time, starting from 0 (s)

% Update payload mass and force of gravity
Mass_Payload = MASS_PAYLOAD;
Gravity_Force_Payload = Mass_Payload * -g;

% After payload detaches, it takes about 1.0 seconds for payload parachute
% to deploy, meanwhile it will be simplified as falling with accel = g

% Loop until time at which payload parachute is fully deployed
while (descentTimePayloadDep <= OPEN_TIME_PAYLOAD_CHUTE)
    % Calculate new position data
    Fy_Total_Payload = Gravity_Force_Payload;
    [ap, vp, sp] = calc_kinematics(Fy_Total_Payload, Mass_Payload, sp0, vp0, t_step);
    
    % Reassign variables for payload
    sp0 = sp; 
    vp0 = vp;
    descentTimePayloadDep = descentTimePayloadDep + t_step;

    % Update payload tracking flight simulation vectors
    spv(j) = sp;
    vpv(j) = vp;
    apv(j) = ap;
    tpv(j) = j * t_step;

    % Update drift radius vectors
    driftp_v0(i)  = WIND0  * t_step * j;
    driftp_v5(i)  = WIND5  * t_step * j;
    driftp_v10(i) = WIND10 * t_step * j;
    driftp_v15(i) = WIND15 * t_step * j;
    driftp_v20(i) = WIND20 * t_step * j;

    % fprintf("G = %8.3f | Fy = %8.3f | a = %8.3f | v = %8.3f | s = %8.3f | t = %8.3f | j = %8.3f\n", ...
    %     Gravity_Force_Payload, Fy_Total_Payload, ap, vp, sp, tpv(j), j); % uncomment for debugging

    % Update looping variable
    j = j + 1;
end
fprintf('Loop 7 complete: j = %d, t = %g, h = %g, \tFlight Event: PAYLOAD CHUTE OPEN\n', ...
    j-1, tpv(j-1), spv(j-1));


%% 8th loop: payload parachute opening to ground impact OF PAYLOAD

% Update payload mass and force of gravity
Mass_Payload = MASS_PAYLOAD - MASS_PAYLOAD_CHUTE;
Gravity_Force_Payload = Mass_Payload * -g;

% Loop until vertical position is 0 for payload
while (sp >= 0)
    % Calculate drag generated from payload parachute
    Payload_Chute_Drag = calc_drag(CD_PAYLOAD_CHUTE, A_PAYLOAD_CHUTE, vp0, sp0+alt);

    % Calculate new position data
    Fy_Total_Payload = Payload_Chute_Drag + Gravity_Force_Payload;
    [ap, vp, sp] = calc_kinematics(Fy_Total_Payload, Mass_Payload, sp0, vp0, t_step);
    
    % Reassign variables for payload
    sp0 = sp; 
    vp0 = vp;
    descentTimePayloadDep = descentTimePayloadDep + t_step;

    % fprintf("D = %8.3f | G = %8.3f | Fy = %8.3f | a = %8.3f | v = %8.3f | s = %8.3f | t = %8.3f\n", ...
    %     Payload_Chute_Drag, Gravity_Force_Payload, Fy_Total_Payload, ap, vp, sp, tpv(j)); % uncomment for debugging

    % Update payload tracking flight simulation vectors
    spv(j) = sp;
    vpv(j) = vp;
    apv(j) = ap;
    tpv(j) = j * t_step;

    % Update drift radius vectors
    driftp_v0(i)  = WIND0  * t_step * j;
    driftp_v5(i)  = WIND5  * t_step * j;
    driftp_v10(i) = WIND10 * t_step * j;
    driftp_v15(i) = WIND15 * t_step * j;
    driftp_v20(i) = WIND20 * t_step * j;

    % Update looping variable
    j = j + 1;
end

% Update looping variable so last index will be last recorded position
j = j - 1;

% Set position data to zero if last altitude measurement was negative
if (sp < 0)
    spv(j) = 0;
end

fprintf('Loop 8 complete: i = %d, t = %g, h = %g, \t\tFlight Event: PAYLOAD TOUCHDOWN\n', ...
    j, tpv(j), spv(j));


%% Final Calculations

% Retrieve mass of each section on landing
Mass_Pay_Landing = MASS_PAYLOAD - MASS_PAYLOAD_CHUTE;
Mass_For_Landing = MASS_FORWARD;
Mass_Cen_Landing = MASS_CENTRAL - MASS_MAIN;
Mass_Aft_Landing = MASS_AFT - MASS_PROP - MASS_DROGUE;

% Retrieve ground impact velocities in ft/s
Final_Velocity_Vehicle = abs(vv(i));
Final_Velocity_Payload = abs(vpv(j));

% Calculate Kinetic Energy of each section at ground impact in ft-lbf
payKE = 0.5 * Mass_Pay_Landing * Final_Velocity_Payload^2;
forKE = 0.5 * Mass_For_Landing * Final_Velocity_Vehicle^2;
cenKE = 0.5 * Mass_Cen_Landing * Final_Velocity_Vehicle^2;
aftKE = 0.5 * Mass_Aft_Landing * Final_Velocity_Vehicle^2;

% Calculate Kinetic Energy of each section under drogue in ft-lbf
forKE_d = 0.5 * (MASS_FORWARD + MASS_PAYLOAD + MASS_CENTRAL) * vt_drogue^2;
aftKE_d = 0.5 * (MASS_AFT - MASS_PROP - MASS_DROGUE) * vt_drogue^2;

% Calculate certain overall performance characteristics
totalTime = tv(i); % Total flight time (s)
descentTimePayload = timePayloadDeployment + descentTimePayloadDep - time2Apogee; % Descent time of payload from apogee (s)
maxV = max(vv(1:apogee_idx)); % Maximum velocity during flight (ft/s)
maxM = maxV / c; % Maximum Mach number during flight (Mach)
maxA = max(av(1:apogee_idx)); % Maximum acceleration experienced by launch vehicle during flight (ft/s^2)
maxG = maxA / g; % Maximum G-loading (G's)

% Format certain results for display in tables
performanceTable = table(["Apogee (ft)"; "Descent Time of Tethered Sections"; ...
    "Descent Time of Payload"; "Rail Exit Velocity (ft/s)"; "Maximum Mach Number"; ...
    "Maximum Velocity (ft/s)"; "Maximum Acceleration (ft/s^2)"; "Maximum G-loading [G]"], ...
    [apogee; descentTime; descentTimePayload; RailExit_V; maxM; maxV; maxA; maxG], ...
    'VariableNames', {'Performance Parameter', 'Result'});

sectionLabels = ["Payload and Nosecone"; "Forward Section"; "Central Section"; "Aft Section"];
KETable = table(sectionLabels, ...
    [Mass_Pay_Landing * g; Mass_For_Landing * g; Mass_Cen_Landing * g; Mass_Aft_Landing * g], ...
    [Final_Velocity_Payload; Final_Velocity_Vehicle; Final_Velocity_Vehicle; Final_Velocity_Vehicle], ...
    [payKE; forKE; cenKE; aftKE], 'VariableNames', {'Section', 'Mass (lbs)', 'Impact Velocity (ft/s)', 'Kinetic Energy (ft-lbf)'});

driftTable = table([0; 5; 10; 15; 20], ...
    [drift_v0(i); drift_v5(i); drift_v10(i); drift_v15(i); drift_v20(i)], ...
    [driftp_v0(i); driftp_v5(i); driftp_v10(i); driftp_v15(i); driftp_v20(i)], ...
    'VariableNames', {'Wind Speed (mph)', 'Vehicle Drift Radius (ft)', ... 
    'Payload Drift Radius (ft)'});

flightProfileTable = table(sectionLabels, ...
    [MASS_PAYLOAD * g; MASS_FORWARD * g; MASS_CENTRAL * g; MASS_AFT * g], ...
    [MASS_PAYLOAD * g; MASS_FORWARD * g; MASS_CENTRAL * g; (MASS_AFT-MASS_PROP) * g], ...
    [Mass_Pay_Landing * g; Mass_For_Landing * g; Mass_Cen_Landing * g; Mass_Aft_Landing * g], ...
    [vt_drogue; vt_drogue; vt_drogue; vt_drogue], ...
    [forKE_d; forKE_d; forKE_d; aftKE_d], ...
    [Final_Velocity_Payload; Final_Velocity_Vehicle; Final_Velocity_Vehicle; Final_Velocity_Vehicle], ...
    [payKE; forKE; cenKE; aftKE], 'VariableNames', ...
    {'Section', 'Lift-off Mass [lbm]', 'Burnout Mass [lbm]', 'Landing Mass [lbm]', 'Drogue Descent Rate [ft/s]', ...
        'Kinetic Energy under Drogue [ft-lbf]', 'Main Descent Rate [ft/s]', 'Kinetic Energy under Main [ft-lbf]'});


%% Display key information

fprintf('\n\nFlight simulation values for a launch angle of %d degrees:\n\n',...
    launchAngle);

fprintf('Apogee: %.2f ft \n', apogee);
fprintf('Time to apogee: %.2f sec \n\n', time2Apogee);

fprintf('Time of payload deployment: t+%.2f sec \n', timePayloadDeployment);
fprintf('Descent time of tethered sections: %.2f sec \n', descentTime);
fprintf('Total flight time tethered sections: %.2f sec \n', totalTime);
fprintf('Descent time payload section from deplyoment: %.2f sec \n\n', ...
    descentTimePayloadDep);

fprintf('Impact velocity of tethered sections: %.2f ft/sec \n', ...
    Final_Velocity_Vehicle);
fprintf('Impact velocity of payload: %.2f ft/sec \n\n', ...
    Final_Velocity_Payload);

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

% Plot the flight simulation vectors for just the vehicle 
plotORdata(sv,vv,av,tv)
title('MATLAB Flight Profile of $Venture$')

% Plot the flight simulation vectors for just the payload
plotORdata(spv,vpv,apv,tpv)
title('MATLAB Flight Profile of Payload $Enter$')



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