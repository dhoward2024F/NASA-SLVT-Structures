function exportFolder = slvtExportResults(results, destination, includeHistories)
%SLVTEXPORTRESULTS Export CSV tables, optional histories, JSON settings, and MAT.
% Creates a fresh subfolder so repeated exports never overwrite an older run.
    if nargin < 3, includeHistories = false; end
    assert(isstruct(results) && isfield(results,'Flights'), 'SLVT:Export', 'No results to export.');
    stamp = datestr(now,'yyyymmdd_HHMMSS');
    base = fullfile(destination,['SLVT_Run_' stamp]);
    exportFolder = base; suffix = 1;
    while exist(exportFolder,'dir')
        exportFolder = [base '_' num2str(suffix)]; suffix = suffix + 1;
    end
    [ok,message] = mkdir(exportFolder);
    assert(ok,'SLVT:Export','Cannot create export folder: %s',message);
    writetable(results.Summary,fullfile(exportFolder,'case_summary.csv'));
    for i = 1:numel(results.Flights)
        f = results.Flights{i};
        prefix = sprintf('flight_%02d_%s_R%d_A%g',i,f.Mode,f.Recovery,f.LaunchAngleDeg);
        t = slvtBuildTables(f,results.Config,results.Selection.WindsMph);
        fields = fieldnames(t);
        for k = 1:numel(fields)
            writetable(t.(fields{k}),fullfile(exportFolder,[prefix '_' lower(fields{k}) '.csv']));
        end
    end
    if includeHistories
        for i = 1:numel(results.Cases)
            c = results.Cases(i); f = results.Flights{c.FlightIndex};
            prefix = sprintf('case_%03d',c.CaseID);
            writetable(slvtTraceTable(f.Vehicle,f.Metrics.TimeToApogeeS,c.WindMph), ...
                fullfile(exportFolder,[prefix '_vehicle_history.csv']));
            if ~isempty(f.Payload)
                writetable(slvtTraceTable(f.Payload,f.Metrics.TimeToApogeeS,c.WindMph), ...
                    fullfile(exportFolder,[prefix '_payload_history.csv']));
            end
        end
    end
    settings = struct('Config',results.Config,'Selection',results.Selection, ...
        'CreatedAt',results.CreatedAt,'Notes',{results.Notes});
    fid = fopen(fullfile(exportFolder,'model_settings.json'),'w');
    assert(fid >= 0,'SLVT:Export','Cannot write model_settings.json.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid,'%s\n',jsonencode(settings));
    % Includes source motor samples, all trajectories, tables, and model snapshot.
    save(fullfile(exportFolder,'SLVT_results.mat'),'results','-v7.3');
end
