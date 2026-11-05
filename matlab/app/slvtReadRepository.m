function plan = slvtReadRepository(repoRoot)
% Read versioned inputs without reading or writing personal app preferences.
    assert(isfolder(repoRoot),'SLVT:Repository','Repository folder not found.');
    [ok,info] = fileattrib(repoRoot); assert(ok); repoRoot = info.Name;
    folder = fullfile(repoRoot,'config');
    v = read('vehicle.json'); l = read('launch_conditions.json');
    a = read('analysis_cases.json'); q = read('requirements.json');
    cfg = slvtDefaultConfig(); notes = {};
    modelPath = fullfile(folder,'matlab_model.json');
    assert(isfile(modelPath),'SLVT:Repository', ...
        'Missing config/matlab_model.json. Copy the supplied file or use Repository > Save model to repository in the app.');
    model = jsondecode(fileread(modelPath));
    names = fieldnames(model.model);
    allowed = fieldnames(cfg);
    shared = {'bodyDiameterIn','finCount','finHeightIn','finThicknessIn', ...
        'totalMassLbm','payloadMassLbm','propellantMassLbm','motorFile', ...
        'drogueDiameterFt','mainDiameterFt','payloadDiameterFt','drogueCd','mainCd','payloadCd', ...
        'siteAltitudeFt','railLengthFt'};
    for i = 1:numel(names)
        assert(ismember(names{i},allowed) && ~ismember(names{i},shared), ...
            'SLVT:Repository','Unknown or shared setting in matlab_model.json: %s.',names{i});
        cfg.(names{i}) = model.model.(names{i});
    end
    % Explicit fallback values cover unresolved null shared inputs only.
    names = fieldnames(model.fallbacks);
    for i = 1:numel(names)
        assert(ismember(names{i},shared) && ~strcmp(names{i},'motorFile'), ...
            'SLVT:Repository','Invalid fallback: %s.',names{i});
        cfg.(names{i}) = model.fallbacks.(names{i});
    end
    assert(strcmpi(v.units,'imperial'),'SLVT:Repository','vehicle.json units must be imperial.');
    map(v.geometry,'body_diameter_in','bodyDiameterIn',1);
    map(v.geometry,'fin_count','finCount',1);
    map(v.geometry,'fin_height_in','finHeightIn',1);
    map(v.geometry,'fin_thickness_in','finThicknessIn',1);
    map(v.mass,'liftoff_lbm','totalMassLbm',1);
    map(v.mass,'payload_lbm','payloadMassLbm',1);
    for pair = {'drogue','main','payload'}
        key = pair{1}; map(v.recovery.(key),'diameter_in',[key 'DiameterFt'],1/12);
        map(v.recovery.(key),'cd',[key 'Cd'],1);
    end
    map(l.launch_site,'elevation_ft','siteAltitudeFt',1);
    map(l.launch,'rail_length_ft','railLengthFt',1);
    if isfield(v.mass,'burnout_lbm') && ~isempty(v.mass.burnout_lbm) && ~all(isnan(v.mass.burnout_lbm))
        burnout = v.mass.burnout_lbm;
        validateattributes(burnout,{'numeric'},{'scalar','finite','positive'});
        total = cfg.totalMassLbm;
        if cfg.useSectionTotal
            total = cfg.payloadMassLbm + cfg.forwardMassLbm + cfg.centralMassLbm + cfg.aftMassLbm;
        end
        cfg.propellantMassLbm = total - burnout;
    else
        notes{end+1} = 'burnout_lbm is null: propellantMassLbm uses the explicit MATLAB fallback.';
    end
    cfg.drogueDelayS = cfg.drogueDelayS(:)'; cfg.mainDeployAltFt = cfg.mainDeployAltFt(:)';
    motorPath = char(v.propulsion.motor_file);
    assert(~isempty(motorPath),'SLVT:Repository','Specify propulsion.motor_file.');
    if ~isAbsolute(motorPath), motorPath = fullfile(repoRoot,motorPath); end
    cfg.motorFile = motorPath;
    assert(isfile(cfg.motorFile),'SLVT:Repository', ...
        'Motor file not found: %s. Add the specified motor curve or explicitly save the desired app model to this repository. No other motor is substituted.',cfg.motorFile);
    validationNotes = slvtValidateConfig(cfg);
    notes = [notes(:); validationNotes(:)];
    slvtReadMotor(cfg.motorFile,cfg.motorThrustUnit);
    cases = slvtExpandRepositoryCases(a,l);
    assert(isfield(q,'requirements') && ~isempty(q.requirements),'SLVT:Repository','No requirements found.');
    notes = [notes(:); {'Vertical model: wind affects descent drift only; lateral ascent position is not modeled.'; ...
        'launch_conditions temperature_F, pressure_Pa, latitude_deg and longitude_deg are recorded but not used by the existing atmosphere model.'; ...
        'Mach and rail-exit velocity are vertical-model estimates, not full 3D flight quantities.'; ...
        'Thrust-to-weight uses burn-average thrust divided by liftoff weight.'; ...
        'Section landing energies use the original section-mass and common vehicle landing-speed conventions.'}];
    plan = struct('Root',repoRoot,'Config',cfg,'Cases',cases,'Requirements',q, ...
        'Notes',{notes},'Vehicle',v,'Launch',l,'Analysis',a,'Model',model);
    function x = read(name)
        file = fullfile(folder,name);
        assert(isfile(file),'SLVT:Repository','Missing config/%s.',name);
        x = jsondecode(fileread(file));
    end
    function map(object,key,target,factor)
        if ~isfield(object,key) || isempty(object.(key)) || all(isnan(object.(key)))
            assert(isfield(model.fallbacks,target),'SLVT:Repository', ...
                'Missing %s and no explicit fallback for %s.',key,target);
            notes{end+1} = sprintf('%s is null: using MATLAB fallback %g for %s.',key,cfg.(target),target);
        else
            validateattributes(object.(key),{'numeric'},{'scalar','real','finite'});
            cfg.(target) = object.(key)*factor;
        end
    end
end
function yes = isAbsolute(p)
    yes = startsWith(p,'/') || startsWith(p,'\') || ~isempty(regexp(p,'^[A-Za-z]:[\\/]','once'));
end
