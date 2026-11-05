classdef SLVTFlightApp < handle
%SLVTFLIGHTAPP Interactive flight/recovery analysis for NASA SLVT.
% Launch from the extracted folder with: app = SLVTFlightApp;
% Programmatic MATLAB app (R2021a or later); no additional toolboxes required.
% Based on David Howard's deploy/retain scripts and Benjamin Putka's model.
    properties (SetAccess = private)
        Config
        Results = []
        UIFigure
        SettingsFile
        RepositoryRoot = ''
    end
    properties (Access = private)
        Editor = []
        EditorTables = {}
        RecoveryTable
        MotorField
        MotorUnits
        AtmosphereChoice
        SectionTotalCheck
        HardwareCheck
        MassNote
        MotorNote
        PayloadChoice
        RecoveryChoice
        AngleChoice
        AngleField
        WindChoice
        WindField
        ModelLabel
        CountLabel
        StatusLabel
        RunButton
        CancelButton
        EditButton
        PresetButton
        ExportButton
        WorkspaceButton
        HistoryCheck
        CaseChoice
        SummaryTable
        PerformanceTable
        SectionTable
        EnergyTable
        DriftTable
        EventTable
        NoteArea
        Tabs
        PlotTab
        PlotGrid
        PlotAxes
        QuantityChoice
        BodyChoice
        CompareCheck
        EventsCheck
        SelectedIndex = 1
        SelectedRows = 1
        IsRunning = false
        CancelRequested = false
        CloseWhenDone = false
        RestoredUI = []
        LoadMessage = ''
    end
    methods
        function app = SLVTFlightApp(settingsFile)
            app.Config = slvtDefaultConfig();
            if nargin < 1
                settingsFile = fullfile(prefdir,'SLVTFlightApp','settings.json');
            end
            app.SettingsFile = char(settingsFile);
            app.loadSettings();
            app.buildUI();
            app.restoreControls();
            app.selectionChanged();
            app.refreshModelLabel();
            app.StatusLabel.Text = 'Ready. Edit model variables, then run a case or the full sweep.';
            if ~isempty(app.LoadMessage), app.StatusLabel.Text = app.LoadMessage; end
        end


        function loadRepository(app,repoRoot)
            assert(~app.IsRunning,'SLVT:Busy','Wait for the active run.');
            plan=slvtReadRepository(repoRoot);
            if ~isempty(app.Editor) && isgraphics(app.Editor), delete(app.Editor); end
            app.Config=plan.Config; app.RepositoryRoot=plan.Root;
            app.refreshModelLabel();
            app.NoteArea.Value=[app.modelNotes(); {'';'REPOSITORY INPUT NOTES:'}; plan.Notes(:)];
            app.StatusLabel.Text='Repository model loaded. Run simulations uses the visible controls; Repository > Run repository cases uses JSON cases.';
        end

        function saveRepository(app,repoRoot)
            assert(~app.IsRunning,'SLVT:Busy','Wait for the active run.');
            slvtSaveRepositoryModel(app.Config,repoRoot);
            app.RepositoryRoot=char(repoRoot);
            app.StatusLabel.Text='Current model and motor saved to repository. Case definitions and requirements preserved.';
        end

        function runRepository(app,repoRoot)
            if nargin<2, repoRoot=app.RepositoryRoot; end
            assert(~isempty(repoRoot),'SLVT:Repository','Choose a repository first.');
            if app.IsRunning, return; end
            dialog=[];
            try
                app.IsRunning=true; app.CancelRequested=false; app.setBusy(true);
                dialog=uiprogressdlg(app.UIFigure,'Title','Repository cases','Cancelable','on','Value',0);
                cleanup=onCleanup(@() app.finishRun(dialog)); %#ok<NASGU>
                [report,results]=slvtRunRepository(repoRoot,[], ...
                    @(fraction,message) app.progress(dialog,fraction,message));
                app.Config=results.Config; app.RepositoryRoot=char(repoRoot); app.Results=results;
                app.SelectedIndex=1; app.SelectedRows=1;
                app.SummaryTable.Data=results.Summary;
                app.SummaryTable.ColumnName=app.prettyNames(results.Summary.Properties.VariableNames);
                app.CaseChoice.Items={results.Cases.Label}; app.CaseChoice.ItemsData=1:numel(results.Cases);
                app.CaseChoice.Value=1; app.CaseChoice.Enable='on';
                app.updateSelected(); app.refreshModelLabel();
                app.NoteArea.Value=[app.modelNotes(); {'';'REPOSITORY RUN NOTES:'}; report.notes(:)];
                app.StatusLabel.Text=sprintf('%d cases exported to results/matlab. %d failed checks; %d not evaluated.', ...
                    report.case_count,report.failed_check_count,report.not_evaluated_count);
            catch problem
                if isempty(dialog), app.IsRunning=false; app.setBusy(false); end
                if isgraphics(app.UIFigure), uialert(app.UIFigure,problem.message,'Repository run'); end
            end
        end

        function delete(app)
            if ~isempty(app.Editor) && isgraphics(app.Editor), delete(app.Editor); end
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure), delete(app.UIFigure); end
        end
    end
    methods (Access = private)
        function buildUI(app)
            app.UIFigure = uifigure('Name','SLVT | Flight and recovery simulator', ...
                'Position',[80 60 1320 830],'Color',[0.96 0.97 0.98], ...
                'CloseRequestFcn',@(~,~) app.closeRequested());

            repoMenu=uimenu(app.UIFigure,'Text','Repository');
            uimenu(repoMenu,'Text','Load model from repository...', ...
                'MenuSelectedFcn',@(~,~) app.repositoryAction('load'));
            uimenu(repoMenu,'Text','Save model to repository...', ...
                'MenuSelectedFcn',@(~,~) app.repositoryAction('save'));
            uimenu(repoMenu,'Text','Run repository cases...', ...
                'MenuSelectedFcn',@(~,~) app.repositoryAction('run'));
            root = uigridlayout(app.UIFigure,[3 2]);
            root.RowHeight = {48,'1x',30}; root.ColumnWidth = {300,'1x'};
            root.Padding = [14 10 14 10]; root.ColumnSpacing = 14;
            slot(uilabel(root,'Text','SLVT  /  Flight and recovery analysis', ...
                'FontSize',22,'FontWeight','bold','FontColor',[0.16 0.23 0.33]),1,[1 2]);
            side = slot(uigridlayout(root,[5 1]),2,1);
            side.RowHeight = {42,54,354,178,'1x'}; side.Padding = [0 0 0 0];
            app.EditButton = slot(uibutton(side,'Text','Edit model variables...', ...
                'FontWeight','bold','ButtonPushedFcn',@(~,~) app.openEditor()),1,1);
            app.ModelLabel = slot(uilabel(side,'WordWrap','on','FontSize',11),2,1);
            runPanel = slot(uipanel(side,'Title','Run matrix'),3,1);
            run = uigridlayout(runPanel,[10 2]);
            run.RowHeight = {28,28,28,28,28,28,28,24,28,28};
            run.ColumnWidth = {104,'1x'}; run.RowSpacing = 3; run.Padding = [8 8 8 8];
            slot(uilabel(run,'Text','Payload'),1,1);
            app.PayloadChoice = slot(uidropdown(run,'Items',{'Both cases','Deploy','Retain (abort)'}, ...
                'ValueChangedFcn',@(~,~) app.selectionChanged()),1,2);
            slot(uilabel(run,'Text','Recovery'),2,1);
            app.RecoveryChoice = slot(uidropdown(run,'Items',{'All 1, 2, 3','1 - Primary','2 - Secondary','3 - Tertiary'}, ...
                'ValueChangedFcn',@(~,~) app.selectionChanged()),2,2);
            slot(uilabel(run,'Text','Launch angle'),3,1);
            app.AngleChoice = slot(uidropdown(run,'Items',{'5 and 10 deg','Custom angle'}, ...
                'ValueChangedFcn',@(~,~) app.selectionChanged()),3,2);
            slot(uilabel(run,'Text','Custom (deg)'),4,1);
            app.AngleField = slot(uieditfield(run,'numeric','Value',5,'Limits',[0 89.99], ...
                'Tooltip','Angle from vertical, matching the original scripts.', ...
                'ValueChangedFcn',@(~,~) app.selectionChanged()),4,2);
            slot(uilabel(run,'Text','Wind speed'),5,1);
            app.WindChoice = slot(uidropdown(run,'Items',{'0:5:20 mph','Custom wind'}, ...
                'ValueChangedFcn',@(~,~) app.selectionChanged()),5,2);
            slot(uilabel(run,'Text','Custom (mph)'),6,1);
            app.WindField = slot(uieditfield(run,'numeric','Value',0,'Limits',[0 Inf], ...
                'ValueChangedFcn',@(~,~) app.selectionChanged()),6,2);
            app.PresetButton = slot(uibutton(run,'Text','Use full sweep', ...
                'ButtonPushedFcn',@(~,~) app.fullSweep()),7,[1 2]);
            app.CountLabel = slot(uilabel(run,'FontWeight','bold'),8,[1 2]);
            app.RunButton = slot(uibutton(run,'Text','Run simulations','FontWeight','bold', ...
                'BackgroundColor',[0.1 0.32 0.53],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~) app.run()),9,[1 2]);
            app.CancelButton = slot(uibutton(run,'Text','Cancel run','Enable','off', ...
                'ButtonPushedFcn',@(~,~) app.requestCancel()),10,[1 2]);
            exportPanel = slot(uipanel(side,'Title','Retrieve results'),4,1);
            eg = uigridlayout(exportPanel,[4 1]); eg.RowHeight = {24,28,28,28}; eg.RowSpacing = 6;
            app.HistoryCheck = slot(uicheckbox(eg,'Text','Include full histories in CSV','Value',false, ...
                'Tooltip','Can create large files for a full sweep; the MAT export always contains full histories.'),1,1);
            app.ExportButton = slot(uibutton(eg,'Text','Export CSV + MAT...', ...
                'Enable','off','ButtonPushedFcn',@(~,~) app.exportResults()),2,1);
            app.WorkspaceButton = slot(uibutton(eg,'Text','Send results to workspace', ...
                'Enable','off','ButtonPushedFcn',@(~,~) app.sendToWorkspace()),3,1);
            slot(uibutton(eg,'Text','Open user guide', ...
                'ButtonPushedFcn',@(~,~) app.openGuide()),4,1);
            slot(uilabel(side,'Text',sprintf(['Settings save after each successful run.\n' ...
                'Angle from vertical; drift from apogee.']), ...
                'WordWrap','on','VerticalAlignment','top','FontColor',[0.32 0.38 0.44]),5,1);
            output = slot(uigridlayout(root,[2 1]),2,2);
            output.RowHeight = {32,'1x'}; output.Padding = [0 0 0 0];
            chooser = slot(uigridlayout(output,[1 2]),1,1);
            chooser.ColumnWidth = {110,'1x'}; chooser.Padding = [0 0 0 0];
            slot(uilabel(chooser,'Text','Selected case','FontWeight','bold'),1,1);
            app.CaseChoice = slot(uidropdown(chooser,'Items',{'Run simulations to select a case'}, ...
                'Enable','off','ValueChangedFcn',@(~,~) app.chooseCase()),1,2);
            app.Tabs = slot(uitabgroup(output),2,1);
            summaryTab = uitab(app.Tabs,'Title','Case summary');
            sg = uigridlayout(summaryTab,[3 1]); sg.RowHeight = {26,'1x',32};
            slot(uilabel(sg,'Text','Select a row to inspect it. Select multiple cells/rows to compare cases.', ...
                'FontColor',[0.32 0.38 0.44]),1,1);
            app.SummaryTable = slot(uitable(sg,'RowName',{}, ...
                'CellSelectionCallback',@(~,event) app.selectSummary(event)),2,1);
            slot(uibutton(sg,'Text','Compare selected summary rows', ...
                'ButtonPushedFcn',@(~,~) app.compareSelected()),3,1);
            detailTab = uitab(app.Tabs,'Title','Flight tables');
            dg = uigridlayout(detailTab,[1 1]); dg.Padding = [0 0 0 0];
            dtabs = uitabgroup(dg);
            app.PerformanceTable = app.makeTableTab(dtabs,'Performance');
            app.SectionTable = app.makeTableTab(dtabs,'Sections and impact KE');
            app.EnergyTable = app.makeTableTab(dtabs,'Drogue tethered groups');
            app.DriftTable = app.makeTableTab(dtabs,'Drift by wind');
            app.EventTable = app.makeTableTab(dtabs,'Flight events');
            app.PlotTab = uitab(app.Tabs,'Title','Plots');
            pg = uigridlayout(app.PlotTab,[3 1]); pg.RowHeight = {34,28,'1x'};
            toolbar = slot(uigridlayout(pg,[1 5]),1,1);
            toolbar.ColumnWidth = {'2x','1x',130,130,120}; toolbar.Padding = [0 0 0 0];
            app.QuantityChoice = slot(uidropdown(toolbar, ...
                'Items',{'Flight profile','Altitude','Vertical velocity','Acceleration', ...
                'Drift history','Drift vs wind','Motor thrust'}, ...
                'ValueChangedFcn',@(~,~) app.updatePlot()),1,1);
            app.BodyChoice = slot(uidropdown(toolbar,'Items',{'Both','Vehicle','Payload'}, ...
                'ValueChangedFcn',@(~,~) app.updatePlot()),1,2);
            slot(uibutton(toolbar,'Text','Open plot figure', ...
                'ButtonPushedFcn',@(~,~) app.openPlot(false)),1,3);
            slot(uibutton(toolbar,'Text','Save plot...', ...
                'ButtonPushedFcn',@(~,~) app.openPlot(true)),1,4);
            app.EventsCheck = slot(uicheckbox(toolbar,'Text','Event lines','Value',true, ...
                'ValueChangedFcn',@(~,~) app.updatePlot()),1,5);
            app.CompareCheck = slot(uicheckbox(pg,'Text','Overlay selected summary rows','Value',false, ...
                'ValueChangedFcn',@(~,~) app.updatePlot()),2,1);
            app.PlotGrid = slot(uigridlayout(pg,[3 1]),3,1); app.PlotGrid.Padding = [4 4 4 4];
            app.PlotAxes = gobjects(1,3);
            for k = 1:3, app.PlotAxes(k) = slot(uiaxes(app.PlotGrid),k,1); end
            notesTab = uitab(app.Tabs,'Title','Model notes');
            ng = uigridlayout(notesTab,[1 1]);
            app.NoteArea = uitextarea(ng,'Editable','off','Value',app.modelNotes());
            app.StatusLabel = slot(uilabel(root,'Text','Ready','FontColor',[0.25 0.31 0.38]),3,[1 2]);
        end


        function repositoryAction(app,action)
            if app.IsRunning, return; end
            start=app.RepositoryRoot; if isempty(start), start=pwd; end
            folder=uigetdir(start,'Select repository root (contains config folder)');
            if isequal(folder,0), return; end
            try
                switch action
                    case 'load', app.loadRepository(folder);
                    case 'save', app.saveRepository(folder);
                    case 'run', app.runRepository(folder);
                end
            catch problem
                uialert(app.UIFigure,problem.message,'Repository configuration');
            end
        end

        function control = makeTableTab(~,parent,titleText)
            tab = uitab(parent,'Title',titleText);
            grid = uigridlayout(tab,[1 1]);
            control = uitable(grid,'RowName',{});
        end

        function selection = getSelection(app)
            switch app.PayloadChoice.Value
                case 'Both cases', modes = {'Deploy','Retain'};
                case 'Deploy', modes = {'Deploy'};
                otherwise, modes = {'Retain'};
            end
            if strcmp(app.RecoveryChoice.Value,'All 1, 2, 3')
                recoveries = 1:3;
            else
                recoveries = str2double(app.RecoveryChoice.Value(1));
            end
            angles = [5 10]; winds = 0:5:20;
            if strcmp(app.AngleChoice.Value,'Custom angle'), angles = app.AngleField.Value; end
            if strcmp(app.WindChoice.Value,'Custom wind'), winds = app.WindField.Value; end
            selection = struct('Modes',{modes},'Recoveries',recoveries,'AnglesDeg',angles,'WindsMph',winds);
        end

        function selectionChanged(app)
            app.AngleField.Enable = onoff(strcmp(app.AngleChoice.Value,'Custom angle') && ~app.IsRunning);
            app.WindField.Enable = onoff(strcmp(app.WindChoice.Value,'Custom wind') && ~app.IsRunning);
            s = app.getSelection();
            vertical = numel(s.Modes)*numel(s.Recoveries)*numel(s.AnglesDeg);
            app.CountLabel.Text = sprintf('%d cases / %d vertical flights',vertical*numel(s.WindsMph),vertical);
        end

        function fullSweep(app)
            app.PayloadChoice.Value = 'Both cases'; app.RecoveryChoice.Value = 'All 1, 2, 3';
            app.AngleChoice.Value = '5 and 10 deg'; app.WindChoice.Value = '0:5:20 mph';
            app.selectionChanged();
        end

        function run(app)
            if app.IsRunning, return; end
            try
                slvtValidateConfig(app.Config);
                app.IsRunning = true; app.CancelRequested = false; app.setBusy(true);
                dialog = uiprogressdlg(app.UIFigure,'Title','Running flight cases', ...
                    'Message','Preparing model...','Cancelable','on','Value',0);
                cleanup = onCleanup(@() app.finishRun(dialog)); %#ok<NASGU>
                results = slvtRunCases(app.Config,app.getSelection(), ...
                    @(fraction,message) app.progress(dialog,fraction,message));
                app.Results = results; app.SelectedIndex = 1; app.SelectedRows = 1;
                app.SummaryTable.Data = results.Summary;
                app.SummaryTable.ColumnName = app.prettyNames(results.Summary.Properties.VariableNames);
                app.CaseChoice.Items = {results.Cases.Label};
                app.CaseChoice.ItemsData = 1:numel(results.Cases); app.CaseChoice.Value = 1;
                app.CaseChoice.Enable = 'on'; app.updateSelected();
                app.NoteArea.Value = [app.modelNotes(); {'';'RUN NOTES:'}; results.Notes(:)];
                app.saveSettings();
                app.StatusLabel.Text = sprintf('Completed %d cases. Model settings saved. Results are ready to export.',numel(results.Cases));
            catch problem
                if isgraphics(app.UIFigure)
                    if strcmp(problem.identifier,'SLVT:Cancelled')
                        app.StatusLabel.Text = 'Run cancelled. Previous results are still available.';
                    else
                        app.StatusLabel.Text = 'Run failed; check the message. Previous results are retained unless the calculation completed.';
                        uialert(app.UIFigure,problem.message,'Simulation / settings error');
                    end
                end
            end
        end

        function stop = progress(app,dialog,fraction,message)
            if ~isempty(dialog) && isvalid(dialog)
                dialog.Value = min(1,max(0,fraction)); dialog.Message = message;
                if dialog.CancelRequested, app.CancelRequested = true; end
            end
            if isgraphics(app.UIFigure), app.StatusLabel.Text = ['Running: ' message]; end
            drawnow limitrate;
            stop = app.CancelRequested || ~isgraphics(app.UIFigure);
        end

        function finishRun(app,dialog)
            if ~isempty(dialog) && isvalid(dialog), close(dialog); end
            app.IsRunning = false;
            if isgraphics(app.UIFigure), app.setBusy(false); end
            if app.CloseWhenDone, delete(app); end
        end

        function setBusy(app,busy)
            controls = {app.PayloadChoice,app.RecoveryChoice,app.AngleChoice,app.WindChoice, ...
                app.RunButton,app.EditButton,app.PresetButton};
            for k = 1:numel(controls), controls{k}.Enable = onoff(~busy); end
            app.CancelButton.Enable = onoff(busy);
            ready = ~busy && ~isempty(app.Results);
            app.ExportButton.Enable = onoff(ready); app.WorkspaceButton.Enable = onoff(ready);
            app.selectionChanged();
        end

        function requestCancel(app)
            app.CancelRequested = true; app.StatusLabel.Text = 'Cancelling...';
        end

        function closeRequested(app)
            if app.IsRunning
                app.CloseWhenDone = true; app.requestCancel();
            else
                delete(app);
            end
        end

        function chooseCase(app)
            if isempty(app.Results), return; end
            app.SelectedIndex = app.CaseChoice.Value; app.SelectedRows = app.SelectedIndex;
            app.updateSelected();
        end

        function selectSummary(app,event)
            if isempty(app.Results) || isempty(event.Indices), return; end
            app.SelectedRows = unique(event.Indices(:,1))';
            app.SelectedIndex = app.SelectedRows(1); app.CaseChoice.Value = app.SelectedIndex;
            app.updateSelected();
        end

        function updateSelected(app)
            if isempty(app.Results), return; end
            c = app.Results.Cases(app.SelectedIndex); f = app.Results.Flights{c.FlightIndex};
            tables = slvtBuildTables(f,app.Results.Config,unique([app.Results.Selection.WindsMph,c.WindMph]));
            controls = {app.PerformanceTable,app.SectionTable,app.EnergyTable,app.DriftTable,app.EventTable};
            data = {tables.Performance,tables.Sections,tables.DrogueGroups,tables.Drift,tables.Events};
            for k = 1:numel(controls)
                controls{k}.Data = data{k};
                controls{k}.ColumnName = app.prettyNames(data{k}.Properties.VariableNames);
            end
            app.updatePlot();
        end

        function compareSelected(app)
            if isempty(app.Results), return; end
            app.CompareCheck.Value = true; app.Tabs.SelectedTab = app.PlotTab; app.updatePlot();
        end

        function indices = plotIndices(app)
            indices = app.SelectedIndex;
            if app.CompareCheck.Value, indices = app.SelectedRows; end
        end

        function updatePlot(app)
            if isempty(app.Results), return; end
            if strcmp(app.QuantityChoice.Value,'Flight profile')
                app.PlotGrid.RowHeight = {'1x','1x','1x'};
            else
                app.PlotGrid.RowHeight = {'1x',0,0};
            end
            slvtPlotResults(app.Results,app.plotIndices(),app.QuantityChoice.Value, ...
                app.BodyChoice.Value,app.EventsCheck.Value,app.PlotAxes);
        end

        function openPlot(app,saveIt)
            if isempty(app.Results), uialert(app.UIFigure,'Run simulations first.','No results'); return; end
            filename = ''; path = '';
            if saveIt
                [filename,path] = uiputfile({'*.png','PNG image';'*.pdf','Vector PDF';'*.fig','MATLAB figure'}, ...
                    'Save flight plot','SLVT_flight_profile.png');
                if isequal(filename,0), return; end
            end
            fig = figure('Name','SLVT flight plot','Color','w','Visible',onoff(~saveIt));
            fig.Position(3:4) = [1050 850];
            rows = 1 + 2*strcmp(app.QuantityChoice.Value,'Flight profile');
            layout = tiledlayout(fig,rows,1,'TileSpacing','compact');
            ax = gobjects(1,3);
            for k = 1:rows, ax(k) = nexttile(layout); end
            if rows == 1
                % Plot helper always takes three axes; hide the unused ones.
                ax(2) = axes(fig,'Visible','off','Position',[0 0 0.001 0.001]);
                ax(3) = axes(fig,'Visible','off','Position',[0 0 0.001 0.001]);
            end
            slvtPlotResults(app.Results,app.plotIndices(),app.QuantityChoice.Value, ...
                app.BodyChoice.Value,app.EventsCheck.Value,ax);
            if saveIt
                cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
                try
                    [~,~,extension] = fileparts(filename);
                    if strcmpi(extension,'.fig')
                        savefig(fig,fullfile(path,filename));
                    elseif strcmpi(extension,'.pdf')
                        exportgraphics(layout,fullfile(path,filename),'ContentType','vector');
                    else
                        exportgraphics(layout,fullfile(path,filename),'Resolution',200);
                    end
                    app.StatusLabel.Text = ['Saved plot: ' fullfile(path,filename)];
                catch problem
                    uialert(app.UIFigure,problem.message,'Plot export error');
                end
            end
        end

        function exportResults(app)
            if isempty(app.Results), return; end
            destination = uigetdir(pwd,'Choose a parent folder for the result export');
            if isequal(destination,0), return; end
            try
                app.StatusLabel.Text = 'Exporting result tables and trajectories...'; drawnow;
                folder = slvtExportResults(app.Results,destination,app.HistoryCheck.Value);
                app.StatusLabel.Text = ['Exported results to ' folder];
            catch problem
                uialert(app.UIFigure,problem.message,'Export error');
            end
        end

        function sendToWorkspace(app)
            if isempty(app.Results), return; end
            c = app.Results.Cases(app.SelectedIndex); f = app.Results.Flights{c.FlightIndex};
            selected.Case = c; selected.Flight = f;
            selected.Tables = slvtBuildTables(f,app.Results.Config,app.Results.Selection.WindsMph);
            selected.VehicleHistory = slvtTraceTable(f.Vehicle,f.Metrics.TimeToApogeeS,c.WindMph);
            selected.PayloadHistory = [];
            if ~isempty(f.Payload)
                selected.PayloadHistory = slvtTraceTable(f.Payload,f.Metrics.TimeToApogeeS,c.WindMph);
            end
            assignin('base','SLVTResults',app.Results);
            assignin('base','SLVTConfig',app.Results.Config);
            assignin('base','SLVTSelected',selected);
            app.StatusLabel.Text = 'Workspace variables: SLVTResults, SLVTConfig, SLVTSelected (replaced if present).';
        end

        function openGuide(~)
            root = fileparts(mfilename('fullpath'));
            web(['file:///' strrep(fullfile(root,'USER_GUIDE.html'),'\','/')],'-browser');
        end

        function refreshModelLabel(app)
            c = app.Config; total = c.totalMassLbm;
            if c.useSectionTotal, total = c.payloadMassLbm+c.forwardMassLbm+c.centralMassLbm+c.aftMassLbm; end
            [~,name,ext] = fileparts(c.motorFile);
            app.ModelLabel.Text = sprintf('Liftoff %.3f lbm | body Cd %.3f\nMotor: %s%s | dt %.4f s',total,c.bodyCd,name,ext,c.timeStepS);
        end

        function openEditor(app)
            if app.IsRunning, return; end
            if ~isempty(app.Editor) && isgraphics(app.Editor)
                app.Editor.Visible = 'on'; return;
            end
            app.Editor = uifigure('Name','SLVT | Edit model variables', ...
                'Position',[180 130 1010 690],'WindowStyle','modal');
            grid = uigridlayout(app.Editor,[4 1]); grid.RowHeight = {30,'1x',44,38};
            slot(uilabel(grid,'Text','Edit values, then Apply and save. Results update on the next run.', ...
                'FontWeight','bold','FontSize',14),1,1);
            tabs = slot(uitabgroup(grid),2,1);
            massTab = uitab(tabs,'Title','Masses');
            mg = uigridlayout(massTab,[3 1]); mg.RowHeight = {'1x',30,30};
            app.EditorTables = {};
            app.addSettingTable(mg,1,{
                'totalMassLbm','Measured total liftoff mass','lbm','Independent total used when section-sum option is off';
                'payloadMassLbm','Payload + nosecone','lbm','Includes its recovery hardware; separated only for Deploy';
                'forwardMassLbm','Forward section','lbm','Excludes detachable payload + nosecone';
                'centralMassLbm','Central section','lbm','Includes main recovery hardware';
                'aftMassLbm','Aft section','lbm','Includes propellant and drogue recovery hardware';
                'propellantMassLbm','Motor propellant','lbm','Consumed linearly during the motor burn';
                'drogueHardwareLbm','Drogue recovery hardware','lbm','Included in aft section';
                'mainHardwareLbm','Main recovery hardware','lbm','Included in central section';
                'payloadHardwareLbm','Payload recovery hardware','lbm','Included in payload + nosecone'});
            app.SectionTotalCheck = slot(uicheckbox(mg,'Text','Use sum of section masses for liftoff mass', ...
                'Value',app.Config.useSectionTotal,'ValueChangedFcn',@(~,~) app.updateEditorMass()),2,1);
            app.HardwareCheck = slot(uicheckbox(mg, ...
                'Text','Exclude open recovery hardware from suspended mass (original convention)', ...
                'Value',app.Config.excludeHardwareMass, ...
                'Tooltip','Clear to include attached recovery hardware in the dynamics and section kinetic energy.'),3,1);
            dragTab = uitab(tabs,'Title','Drag and geometry');
            gg = uigridlayout(dragTab,[1 1]);
            app.addSettingTable(gg,1,{
                'bodyCd','Vehicle body Cd','-','Ascent drag coefficient';
                'drogueCd','Drogue Cd','-','Drogue parachute drag coefficient';
                'mainCd','Main Cd','-','Main parachute drag coefficient';
                'payloadCd','Payload chute Cd','-','Payload parachute drag coefficient';
                'bodyDiameterIn','Body diameter','in','Used for frontal area';
                'finHeightIn','Fin height','in','Exposed fin-edge area';
                'finThicknessIn','Fin thickness','in','Exposed fin-edge area';
                'finCount','Number of fins','integer','Total fin-edge area = N * height * thickness';
                'railLengthFt','Effective rail length','ft','Original vertical threshold for rail exit';
                'drogueDiameterFt','Drogue diameter','ft','Circular reference area';
                'mainDiameterFt','Main diameter','ft','Circular reference area';
                'payloadDiameterFt','Payload chute diameter','ft','Circular reference area'});
            recoveryTab = uitab(tabs,'Title','Recovery timing');
            rg = uigridlayout(recoveryTab,[3 1]); rg.RowHeight = {140,24,'1x'};
            data = cell(3,3);
            labels = {'1 - Primary';'2 - Secondary';'3 - Tertiary'};
            for k = 1:3, data(k,:) = {labels{k},app.Config.drogueDelayS(k),app.Config.mainDeployAltFt(k)}; end
            app.RecoveryTable = slot(uitable(rg,'Data',data,'RowName',{}, ...
                'ColumnName',{'Recovery configuration','Drogue delay after apogee (s)','Main command altitude (ft AGL)'}, ...
                'ColumnEditable',[false true true],'ColumnFormat',{'char','numeric','numeric'}, ...
                'ColumnWidth',{180,260,280}),1,1);
            slot(uilabel(rg,'Text','The main opening model retains the original altitude-offset approximation.'),2,1);
            app.addSettingTable(rg,3,{
                'payloadDeployAltFt','Payload release altitude','ft AGL','Deploy case only; follows main fully opening';
                'drogueOpenS','Drogue opening time','s','Added to the selected post-apogee drogue delay';
                'mainOpenS','Main opening time','s','Main full-open altitude offset = opening time * terminal estimate';
                'payloadOpenS','Payload chute opening time','s','Payload free fall duration after release'});
            environmentTab = uitab(tabs,'Title','Environment and numerics');
            vg = uigridlayout(environmentTab,[3 1]); vg.RowHeight = {'1x',28,32};
            app.addSettingTable(vg,1,{
                'siteAltitudeFt','Launch site elevation','ft ASL','Added to AGL altitude for drag density';
                'g','Gravity / mass conversion constant','ft/s^2','32.174 reproduces the original mass convention';
                'soundSpeedFtS','Speed of sound','ft/s','Constant value for maximum Mach';
                'timeStepS','Integration time step','s','Default 0.001; allowed 0.0001 to 0.02';
                'maxTimeS','Maximum trajectory time','s','Stops invalid or non-landing trajectories'});
            slot(uilabel(vg,'Text','Atmosphere density provider'),2,1);
            app.AtmosphereChoice = slot(uidropdown(vg, ...
                'Items',{'Built-in 1976 standard atmosphere','External atmos.m (original helper)'}, ...
                'ItemsData',{'standard','external'},'Value',app.Config.atmosphere),3,1);
            motorTab = uitab(tabs,'Title','Motor curve');
            fg = uigridlayout(motorTab,[6 2]);
            fg.RowHeight = {28,34,34,34,68,'1x'}; fg.ColumnWidth = {'1x',140};
            slot(uilabel(fg,'Text','CSV: time, thrust. Single-motor RASP .eng: seconds, newtons.'),1,[1 2]);
            app.MotorField = slot(uieditfield(fg,'text','Value',char(app.Config.motorFile)),2,1);
            slot(uibutton(fg,'Text','Browse...', 'ButtonPushedFcn',@(~,~) app.browseMotor()),2,2);
            slot(uilabel(fg,'Text','CSV thrust units (.eng always N)'),3,1);
            app.MotorUnits = slot(uidropdown(fg,'Items',{'N','lbf'},'Value',app.Config.motorThrustUnit),3,2);
            slot(uibutton(fg,'Text','Validate and preview thrust curve', ...
                'ButtonPushedFcn',@(~,~) app.previewMotor()),4,[1 2]);
            app.MotorNote = slot(uilabel(fg,'Text','Select a motor file, then preview to check its burn time and impulse.', ...
                'WordWrap','on','VerticalAlignment','top'),5,[1 2]);
            slot(uilabel(fg,'Text',['The selected motor file is saved with your model settings. ' ...
                'Update propellant mass on the Masses tab when changing motors.'], ...
                'WordWrap','on','VerticalAlignment','top'),6,[1 2]);
            app.MassNote = slot(uilabel(grid,'WordWrap','on','FontColor',[0.52 0.30 0.04]),3,1);
            buttons = slot(uigridlayout(grid,[1 3]),4,1);
            buttons.Padding = [0 0 0 0]; buttons.ColumnWidth = {180,'1x',160};
            slot(uibutton(buttons,'Text','Load original defaults', ...
                'ButtonPushedFcn',@(~,~) app.resetEditor()),1,1);
            slot(uibutton(buttons,'Text','Apply and save','FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) app.applyEditor()),1,2);
            slot(uibutton(buttons,'Text','Cancel','ButtonPushedFcn',@(~,~) delete(app.Editor)),1,3);
            app.updateEditorMass();
        end

        function addSettingTable(app,parent,row,schema)
            data = cell(size(schema,1),4);
            data(:,[1 3 4]) = schema(:,2:4);
            for k = 1:size(schema,1), data{k,2} = app.Config.(schema{k,1}); end
            control = slot(uitable(parent,'Data',data,'RowName',{}, ...
                'ColumnName',{'Variable','Value','Units','Meaning'}, ...
                'ColumnEditable',[false true false false], ...
                'ColumnFormat',{'char','numeric','char','char'}, ...
                'ColumnWidth',{235,105,80,'auto'}, ...
                'UserData',schema,'CellEditCallback',@(~,~) app.updateEditorMass()),row,1);
            app.EditorTables{end+1} = control;
        end

        function candidate = editorConfig(app)
            candidate = app.Config;
            for i = 1:numel(app.EditorTables)
                tableControl = app.EditorTables{i}; schema = tableControl.UserData;
                for k = 1:size(schema,1)
                    value = tableControl.Data{k,2};
                    assert(isnumeric(value) && isscalar(value) && isfinite(value), ...
                        'SLVT:Config','Enter a finite numeric value for %s.',schema{k,2});
                    candidate.(schema{k,1}) = value;
                end
            end
            candidate.drogueDelayS = cell2mat(app.RecoveryTable.Data(:,2))';
            candidate.mainDeployAltFt = cell2mat(app.RecoveryTable.Data(:,3))';
            candidate.useSectionTotal = app.SectionTotalCheck.Value;
            candidate.excludeHardwareMass = app.HardwareCheck.Value;
            candidate.atmosphere = app.AtmosphereChoice.Value;
            candidate.motorFile = strtrim(app.MotorField.Value);
            candidate.motorThrustUnit = app.MotorUnits.Value;
        end

        function updateEditorMass(app)
            if isempty(app.MassNote) || ~isgraphics(app.MassNote), return; end
            try
                candidate = app.editorConfig();
                sumMass = candidate.payloadMassLbm + candidate.forwardMassLbm + ...
                    candidate.centralMassLbm + candidate.aftMassLbm;
                if candidate.useSectionTotal
                    app.MassNote.Text = sprintf('Section-sum liftoff mass: %.4f lbm. Measured-total entry is ignored.',sumMass);
                else
                    app.MassNote.Text = sprintf('Measured total: %.4f lbm | Section sum: %.4f lbm | Difference: %+.4f lbm.', ...
                        candidate.totalMassLbm,sumMass,candidate.totalMassLbm-sumMass);
                end
            catch
                app.MassNote.Text = 'One or more values are incomplete or invalid. Correct them before applying.';
            end
        end

        function applyEditor(app)
            try
                candidate = app.editorConfig();
                slvtValidateConfig(candidate);
                slvtReadMotor(candidate.motorFile,candidate.motorThrustUnit);
                previous = app.Config; app.Config = candidate;
                try
                    app.saveSettings();
                catch problem
                    app.Config = previous; rethrow(problem);
                end
                app.refreshModelLabel(); delete(app.Editor);
                app.StatusLabel.Text = 'Model settings saved. Run simulations to calculate results with the updated model.';
            catch problem
                uialert(app.Editor,problem.message,'Check model variables');
            end
        end

        function resetEditor(app)
            cfg = slvtDefaultConfig();
            for i = 1:numel(app.EditorTables)
                control = app.EditorTables{i}; schema = control.UserData; data = control.Data;
                for k = 1:size(schema,1), data{k,2} = cfg.(schema{k,1}); end
                control.Data = data;
            end
            data = app.RecoveryTable.Data;
            for k = 1:3, data{k,2} = cfg.drogueDelayS(k); data{k,3} = cfg.mainDeployAltFt(k); end
            app.RecoveryTable.Data = data;
            app.SectionTotalCheck.Value = cfg.useSectionTotal;
            app.HardwareCheck.Value = cfg.excludeHardwareMass;
            app.AtmosphereChoice.Value = cfg.atmosphere;
            app.MotorField.Value = cfg.motorFile; app.MotorUnits.Value = cfg.motorThrustUnit;
            app.updateEditorMass();
        end

        function browseMotor(app)
            [filename,path] = uigetfile({'*.csv;*.eng','Motor curves (*.csv, *.eng)'},'Select motor thrust curve');
            if isequal(filename,0), return; end
            app.MotorField.Value = fullfile(path,filename);
        end

        function previewMotor(app)
            try
                motor = slvtReadMotor(app.MotorField.Value,app.MotorUnits.Value);
                app.MotorNote.Text = sprintf('Burn %.3f s | Impulse %.2f lbf-s | Average %.2f lbf | Peak %.2f lbf', ...
                    motor.BurnTimeS,motor.ImpulseLbfS,motor.AverageThrustLbf,motor.PeakThrustLbf);
                fig = figure('Name','Motor thrust preview','Color','w');
                ax = axes(fig); plot(ax,motor.TimeS,motor.ThrustLbf,'LineWidth',1.7); grid(ax,'on');
                xlabel(ax,'Time (s)'); ylabel(ax,'Thrust (lbf)'); title(ax,'Selected motor curve');
            catch problem
                uialert(app.Editor,problem.message,'Motor CSV error');
            end
        end

        function loadSettings(app)
            if ~exist(app.SettingsFile,'file'), return; end
            try
                saved = jsondecode(fileread(app.SettingsFile));
                fields = fieldnames(app.Config);
                for k = 1:numel(fields)
                    if isfield(saved.Config,fields{k}), app.Config.(fields{k}) = saved.Config.(fields{k}); end
                end
                app.Config.drogueDelayS = app.Config.drogueDelayS(:)';
                app.Config.mainDeployAltFt = app.Config.mainDeployAltFt(:)';
                if ~exist(app.Config.motorFile,'file')
                    [~,n,e] = fileparts(app.Config.motorFile);
                    candidate = fullfile(fileparts(mfilename('fullpath')),[n e]);
                    if exist(candidate,'file'), app.Config.motorFile = candidate; end
                end
                slvtValidateConfig(app.Config);
                if isfield(saved,'UI'), app.RestoredUI = saved.UI; end
                app.LoadMessage = 'Previous model settings restored. Ready to run.';
            catch problem
                app.Config = slvtDefaultConfig();
                app.LoadMessage = ['Could not restore previous settings; defaults loaded. ' problem.message];
            end
        end

        function restoreControls(app)
            if isempty(app.RestoredUI), return; end
            names = {'PayloadChoice','RecoveryChoice','AngleChoice','WindChoice','AngleField','WindField'};
            for k = 1:numel(names)
                if isfield(app.RestoredUI,names{k})
                    try, app.(names{k}).Value = app.RestoredUI.(names{k}); catch, end
                end
            end
        end

        function saveSettings(app)
            folder = fileparts(app.SettingsFile);
            if isempty(folder), folder = pwd; end
            if ~exist(folder,'dir')
                [ok,message] = mkdir(folder); assert(ok,'SLVT:Settings','Cannot create settings folder: %s',message);
            end
            names = {'PayloadChoice','RecoveryChoice','AngleChoice','WindChoice','AngleField','WindField'};
            ui = struct();
            for k = 1:numel(names), ui.(names{k}) = app.(names{k}).Value; end
            saved = struct('Config',app.Config,'UI',ui,'SavedAt',datestr(now,30));
            temporary = [tempname(folder) '.json'];
            fid = fopen(temporary,'w'); assert(fid >= 0,'SLVT:Settings','Cannot write settings file.');
            try
                fprintf(fid,'%s\n',jsonencode(saved)); fclose(fid);
                [ok,message] = movefile(temporary,app.SettingsFile,'f');
                assert(ok,'SLVT:Settings','Cannot save settings: %s',message);
            catch problem
                if any(fopen('all') == fid), fclose(fid); end
                if exist(temporary,'file'), delete(temporary); end
                rethrow(problem);
            end
        end

        function names = prettyNames(~,names)
            for k = 1:numel(names)
                text = names{k};
                text = strrep(text,'FtLbf',' (ft-lbf)'); text = strrep(text,'FtS2',' (ft/s^2)');
                text = strrep(text,'FtS',' (ft/s)'); text = strrep(text,'Lbm',' (lbm)');
                text = strrep(text,'Mph',' (mph)'); text = strrep(text,'Deg',' (deg)');
                text = strrep(text,'Ft',' (ft)');
                if ~isempty(text) && text(end) == 'S', text = [text(1:end-1) ' (s)']; end
                names{k} = regexprep(text,'([a-z])([A-Z])','$1 $2');
            end
        end

        function notes = modelNotes(~)
            notes = {'Model inherited from the supplied SLVT deploy / retain scripts.'; ...
                ''; 'Newton: a = F/m. Kinematics: v = v0 + a*dt; h = h0 + (v0+v)*dt/2.'; ...
                'All calculations use ft, s, lbf, and slugs. Editor masses are lbm; mass_slugs = mass_lbm/g.'; ...
                'Launch angle is measured from vertical; thrust and ascent drag are projected with cos(angle).'; ...
                'Drag uses vertical speed, constant Cd, body frontal area plus fin-edge area.'; ...
                'Propellant burns at a constant mass rate. Gravity and sound speed are constant.'; ...
                'Rail exit uses the original effective rail length as a vertical-altitude threshold.'; ...
                'Mach is vertical velocity / configured sound speed; max net G is max acceleration / g.'; ...
                'Descent neglects body drag. Chutes apply their full drag at the opening event.'; ...
                'Drogue opens at apogee + selected delay + drogue opening time.'; ...
                'Main fully-open altitude = selected main altitude - main opening time * drogue terminal estimate.'; ...
                'That terminal estimate uses AGL density as in the scripts; all drag forces use ASL density.'; ...
                'Payload release follows main opening. Payload is in free fall until its chute fully opens.'; ...
                'Exclude open recovery hardware mass defaults ON to preserve the scripts'' suspended-mass convention.'; ...
                'Turn it OFF to include attached recovery mass; this changes trajectories and KE results.'; ...
                'Retain (abort) combines the forward section with the payload/nosecone and keeps it attached.'; ...
                ''; 'Wind: drift = wind_ft/s * elapsed_time_since_apogee. No lateral ascent position is modeled.'; ...
                'Wind does not change apogee, recovery timing, descent speed, or impact KE in this model.'; ...
                'Retained payload has no independent trajectory; payload-only metrics are NaN (not applicable).'; ...
                ''; 'Corrections made during conversion:'; ...
                '- Motor CSV metadata is skipped; numeric columns are extracted and thrust units are explicit.'; ...
                '- Interpolation is done once at actual burn times, starting from (0,0) when missing.'; ...
                '- Payload drift uses its own touchdown time relative to the shared apogee, fixing the i/j indexing error.'; ...
                '- Event crossings and touchdown are located within a step; timestamps and altitude are aligned.'; ...
                '- No fixed 100000-sample limit. Invalid inputs, unstable steps, and missing deployments produce errors.'; ...
                '- Individual section drogue KE and combined tethered-group KE are reported separately.'; ...
                ''; 'Built-in density uses the 1976 standard lower atmosphere (-1500 to 65000 ft ASL).'; ...
                'Select External atmos.m in the editor if you want to use your original density function.'; ...
                'The independently specified liftoff mass is preserved; section-sum discrepancies are shown.'; ...
                ''; 'Results hold a snapshot of all model settings and the source motor curve.'; ...
                'Editing the model affects the next run; already displayed results retain their original inputs.'; ...
                'Select multiple summary rows to overlay plots. Duplicate wind cases share one vertical curve.'};
        end
    end
end

function handle = slot(handle,row,column)
    handle.Layout.Row = row; handle.Layout.Column = column;
end

function text = onoff(value)
    if value, text = 'on'; else, text = 'off'; end
end
