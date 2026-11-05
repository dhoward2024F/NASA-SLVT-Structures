function [report,results] = slvtRunRepository(repoRoot,outputDir,progress)
% Headless shared-engine run. No UI, preferences, prompts, figures, or cwd changes.
% report = slvtRunRepository(repoRoot) writes results/matlab.
    if nargin<2 || isempty(outputDir), outputDir=fullfile(repoRoot,'results','matlab'); end
    if nargin<3, progress=@(fraction,message) false; end
    plan=slvtReadRepository(repoRoot); cfg=plan.Config; defs=plan.Cases;
    motor=slvtReadMotor(cfg.motorFile,cfg.motorThrustUnit);
    cache=containers.Map('KeyType','char','ValueType','double'); flights={};
    rows=struct([]); sectionRows=struct([]); checks=struct([]);
    cases=struct('CaseID',{},'Label',{},'FlightIndex',{},'Mode',{},'Recovery',{},'LaunchAngleDeg',{},'WindMph',{});
    errors={}; summaryRows=cell(0,17); recoveryNames={'primary','secondary','tertiary'};
    for i=1:numel(defs)
        d=defs(i); recovery=find(strcmp(d.recovery_configuration,recoveryNames));
        mode='Retain'; if strcmp(d.payload_deployment,'deploy'), mode='Deploy'; end
        if progress((i-1)/numel(defs),d.name), error('SLVT:Cancelled','Run cancelled.'); end
        key=sprintf('%s|%d|%.17g',mode,recovery,d.launch_angle_from_vertical_deg);
        row=struct('case_name',d.name,'payload_deployment',d.payload_deployment, ...
            'recovery_configuration',d.recovery_configuration, ...
            'launch_angle_from_vertical_deg',d.launch_angle_from_vertical_deg,'wind_speed_mph',d.wind_speed_mph, ...
            'apogee_ft',NaN,'thrust_to_weight_ratio',NaN,'rail_exit_velocity_fps',NaN, ...
            'max_mach',NaN,'max_velocity_fps',NaN,'max_accel_g',NaN,'descent_time_s',NaN, ...
            'landing_drift_ft',NaN,'max_landing_kinetic_energy_ft_lbf',NaN,'run_status','ok','error','');
        sections=struct([]);
        try
            if isKey(cache,key)
                fi=cache(key); f=flights{fi};
            else
                f=slvtSimulate(cfg,motor,mode,recovery,d.launch_angle_from_vertical_deg, ...
                    @() progress((i-1)/numel(defs),d.name));
                fi=numel(flights)+1; flights{fi}=f; cache(key)=fi;
            end
            m=f.Metrics;
            row.apogee_ft=m.ApogeeFt; row.thrust_to_weight_ratio=m.AverageThrustToWeight;
            row.rail_exit_velocity_fps=m.RailExitVelocityFtS;
            % Scan both full trajectories, including descent, for the Mach check.
            speeds=abs(f.Vehicle(:,3));
            if ~isempty(f.Payload), speeds=[speeds;abs(f.Payload(:,3))]; end
            row.max_mach=max(speeds)/cfg.soundSpeedFtS;
            row.max_velocity_fps=max(speeds); row.max_accel_g=m.MaxNetG;
            sd=slvtSectionData(f,cfg);
            for j=1:numel(sd)
                duration=m.VehicleDescentTimeS;
                if strcmp(mode,'Deploy') && j==1, duration=m.PayloadDescentTimeS; end
                sections(j)=struct('case_name',d.name,'name',sd(j).Section, ...
                    'landing_mass_lbm',sd(j).LandingMassLbm,'impact_velocity_fps',sd(j).ImpactVelocityFtS, ...
                    'landing_kinetic_energy_ft_lbf',sd(j).ImpactKEFtLbf, ...
                    'landing_drift_ft',d.wind_speed_mph*5280/3600*duration,'descent_time_s',duration); %#ok<AGROW>
            end
            row.descent_time_s=max([sections.descent_time_s]);
            row.landing_drift_ft=max([sections.landing_drift_ft]);
            row.max_landing_kinetic_energy_ft_lbf=max([sections.landing_kinetic_energy_ft_lbf]);
            cases(end+1)=struct('CaseID',i,'Label',d.name,'FlightIndex',fi,'Mode',mode, ...
                'Recovery',recovery,'LaunchAngleDeg',d.launch_angle_from_vertical_deg,'WindMph',d.wind_speed_mph);
            summaryRows(end+1,:)={i,mode,recovery,d.launch_angle_from_vertical_deg,d.wind_speed_mph,m.ApogeeFt, ...
                m.RailExitVelocityFtS,m.MaxMach,m.MaxVelocityFtS,m.MaxAccelerationFtS2, ...
                m.VehicleDescentTimeS,m.PayloadDescentTimeS,m.VehicleImpactVelocityFtS,m.PayloadImpactVelocityFtS, ...
                d.wind_speed_mph*5280/3600*m.VehicleDescentTimeS, ...
                d.wind_speed_mph*5280/3600*m.PayloadDescentTimeS,m.MainFullyOpenEstimateFt};
        catch problem
            if strcmp(problem.identifier,'SLVT:Cancelled'), rethrow(problem); end
            row.run_status='error'; row.error=problem.message;
            errors{end+1}=sprintf('%s: %s',d.name,problem.message); %#ok<AGROW>
        end
        rows=[rows row]; sectionRows=[sectionRows sections]; %#ok<AGROW>
        evaluated=slvtEvaluateRequirements(plan.Requirements.requirements,row,sections,d.name);
        checks=[checks evaluated]; %#ok<AGROW>
    end
    report=struct('schema_version',1,'assessment','model_estimate','created_at',datestr(now,30), ...
        'git_commit',getenv('GITHUB_SHA'),'case_count',numel(defs),'unique_vertical_flights',numel(flights), ...
        'notes',{[plan.Notes(:);motor.Notes(:)]},'cases',rows,'sections',sectionRows,'requirements',checks, ...
        'simulation_error_count',numel(errors),'failed_check_count',sum(strcmp({checks.status},'fail')), ...
        'not_evaluated_count',sum(strcmp({checks.status},'not_evaluated')));
    results=struct('Config',cfg,'Motor',motor,'Flights',{flights},'Cases',cases, ...
        'Selection',struct('Modes',{{'Deploy','Retain'}},'Recoveries',1:3, ...
            'AnglesDeg',unique([defs.launch_angle_from_vertical_deg]),'WindsMph',unique([defs.wind_speed_mph])), ...
        'Notes',{report.notes},'CreatedAt',report.created_at,'RepositoryReport',report);
    if exist('cell2table','file')
        results.Summary=cell2table(summaryRows,'VariableNames', ...
            {'CaseID','PayloadMode','Recovery','LaunchAngleDeg','WindMph','ApogeeFt', ...
            'RailExitVelocityFtS','MaxMach','MaxVelocityFtS','MaxAccelerationFtS2', ...
            'VehicleDescentTimeS','PayloadDescentTimeS','VehicleImpactVelocityFtS', ...
            'PayloadImpactVelocityFtS','VehicleDriftFt','PayloadDriftFt','MainFullyOpenEstimateFt'});
    end
    if ~exist(outputDir,'dir'), mkdir(outputDir); end
    slvtWriteJSON(fullfile(outputDir,'summary.json'),report);
    slvtWriteJSON(fullfile(outputDir,'resolved_model.json'),cfg);
    snapshots=fullfile(outputDir,'inputs'); if ~exist(snapshots,'dir'), mkdir(snapshots); end
    for name={'vehicle','launch_conditions','analysis_cases','requirements','matlab_model'}
        copyfile(fullfile(plan.Root,'config',[name{1} '.json']),fullfile(snapshots,[name{1} '.json']));
    end
    [~,motorName,motorExt]=fileparts(cfg.motorFile);
    copyfile(cfg.motorFile,fullfile(snapshots,['motor_' motorName motorExt]));
    slvtWriteStructCSV(fullfile(outputDir,'case_summary.csv'),rows);
    slvtWriteStructCSV(fullfile(outputDir,'sections.csv'),sectionRows);
    slvtWriteStructCSV(fullfile(outputDir,'requirements.csv'),checks);
    progress(1,'Complete');
    if ~isempty(errors)
        error('SLVT:RepositoryRun','%d cases failed; details written to %s.',numel(errors),outputDir);
    end
end
