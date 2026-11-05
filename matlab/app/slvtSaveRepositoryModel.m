function slvtSaveRepositoryModel(cfg,repoRoot)
% Explicitly publish the current app model. Does not alter cases or requirements.
    slvtValidateConfig(cfg); slvtReadMotor(cfg.motorFile,cfg.motorThrustUnit);
    folder=fullfile(repoRoot,'config');
    assert(isfile(fullfile(folder,'vehicle.json')) && isfile(fullfile(folder,'launch_conditions.json')), ...
        'SLVT:Repository','Copy the supplied config folder into this repository first.');
    v=jsondecode(fileread(fullfile(folder,'vehicle.json')));
    l=jsondecode(fileread(fullfile(folder,'launch_conditions.json')));
    v.units='imperial';
    v.geometry=struct('body_diameter_in',cfg.bodyDiameterIn,'fin_count',cfg.finCount, ...
        'fin_height_in',cfg.finHeightIn,'fin_thickness_in',cfg.finThicknessIn);
    total=cfg.totalMassLbm;
    if cfg.useSectionTotal, total=cfg.payloadMassLbm+cfg.forwardMassLbm+cfg.centralMassLbm+cfg.aftMassLbm; end
    v.mass.liftoff_lbm=total; v.mass.burnout_lbm=total-cfg.propellantMassLbm; v.mass.payload_lbm=cfg.payloadMassLbm;
    for pair={'drogue','main','payload'}
        key=pair{1}; v.recovery.(key).diameter_in=cfg.([key 'DiameterFt'])*12;
        v.recovery.(key).cd=cfg.([key 'Cd']);
    end
    l.launch_site.elevation_ft=cfg.siteAltitudeFt; l.launch.rail_length_ft=cfg.railLengthFt;
    [~,name,ext]=fileparts(cfg.motorFile);
    dest=fullfile(repoRoot,'matlab','data','motors'); if ~isfolder(dest), mkdir(dest); end
    target=fullfile(dest,[name ext]);
    [~,sourceInfo]=fileattrib(cfg.motorFile);
    if isfile(target), [~,targetInfo]=fileattrib(target); same=strcmp(sourceInfo.Name,targetInfo.Name); else, same=false; end
    if ~same, copyfile(cfg.motorFile,target); end
    v.propulsion.motor_name=name; v.propulsion.motor_file=['matlab/data/motors/' name ext];
    shared={'bodyDiameterIn','finCount','finHeightIn','finThicknessIn', ...
        'totalMassLbm','payloadMassLbm','propellantMassLbm','motorFile', ...
        'drogueDiameterFt','mainDiameterFt','payloadDiameterFt','drogueCd','mainCd','payloadCd', ...
        'siteAltitudeFt','railLengthFt'};
    model=rmfield(cfg,shared); fallbacks=struct();
    for k=1:numel(shared)
        if ~strcmp(shared{k},'motorFile'), fallbacks.(shared{k})=cfg.(shared{k}); end
    end
    % Put the measured effective total in the fallback as well.
    fallbacks.totalMassLbm=total;
    slvtWriteJSON(fullfile(folder,'vehicle.json'),v);
    slvtWriteJSON(fullfile(folder,'launch_conditions.json'),l);
    slvtWriteJSON(fullfile(folder,'matlab_model.json'),struct('schema_version',1,'model',model,'fallbacks',fallbacks));
end
