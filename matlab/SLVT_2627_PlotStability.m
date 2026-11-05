%% Plot Stability Curve from CSV File
% Author: David Howard
% For use by NASA SLVT
% Version: 10/28/2026

clear, clc, close all

% INPUT file name of data, CHECK column indices: [time, stability]
FILENAME = "Seeker_flightProfileData_OR";

% Save outputs?
saveOutputs = false;


%% Setup

% Import CSV stability data
data = readtable(FILENAME);
time_steps = table2array(data(:,1)); % extract time steps
stability_steps = table2array(data(:,5)); % extract stability steps

% Find flight events and times
lines = readlines(FILENAME);
eventRows = startsWith(strtrim(lines), "# Event");
eventLines = lines(eventRows);
eventTimes = nan(length(eventLines),1);
for i = 1:length(eventLines)
    token = regexp(eventLines(i), 't=([0-9.]+)', 'tokens', 'once');
    if ~isempty(token)
        eventTimes(i) = str2double(token{1});
    end
end

% Trim any NaN and resize
valid = ~isnan(time_steps) & ~isnan(stability_steps);
time_steps = time_steps(valid);
stability_steps = stability_steps(valid);
firstNegative = find(stability_steps < 0, 1, 'first');
if ~isempty(firstNegative)
    time_steps = time_steps(1:firstNegative-1);
    stability_steps = stability_steps(1:firstNegative-1);
end

% Output directory
baseDir = fileparts(mfilename('fullpath'));
%outDir = fullfile(baseDir, 'Lab2_Results');
outDir = baseDir;
%if saveOutputs && ~isfolder(outDir), mkdir(outDir); end

%% Plot results

% Set default plot settings
set(groot,'defaultfigurecolor','w');
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultTextInterpreter','latex');
set(groot,'defaultLegendInterpreter','latex');
set(groot,'defaultAxesTickLabelInterpreter','latex');
set(groot,'defaultAxesFontSize',16);
set(groot,'defaultLineLineWidth',2);

% Flight events to plot
eventNames = ["Event: Launch","Event: Liftoff","Event: Launch Rod",...
    "Event: Burnout","Event: Apogee"];
eventIndices = [2, 3, 4, 6, 8]; % CHECK

% Plot stability
f = figure(Theme="light");
plot(time_steps,stability_steps,"Color","b","LineWidth",1.5)
hold on; grid on
% for event = eventIndices
%     j = find(eventIndices,event)
%     eventTime = eventTimes(event);
%     eventName = eventNames(event);
%     xline(eventTime, '--k','DisplayName',eventName);
% end
xlabel("Time (s)"); ylabel("Stabiliy Margin (cal)");
title("Stability Margin Throughout Ascent")
legend({"In-flight Stability","Static Stability","NASA SLI Req. 2.13"}, ...
    "Location","southeast")
axis([0,time_steps(end),0,max(stability_steps)+0.25])

% Export graphic
if saveOutputs
    exportgraphics(f,'stabilityPlot.png','Resolution',300);
end