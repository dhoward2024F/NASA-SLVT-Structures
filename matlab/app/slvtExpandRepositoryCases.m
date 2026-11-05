function cases = slvtExpandRepositoryCases(a,launch)
% Preserve explicit angle/wind pairs; do not form an unintended larger sweep.
    cases = struct('name',{},'wind_speed_mph',{},'launch_angle_from_vertical_deg',{}, ...
        'recovery_configuration',{},'payload_deployment',{});
    assert(isfield(a,'cases') && isstruct(a.cases),'SLVT:Case','analysis_cases.json needs a cases array.');
    for k = 1:numel(a.cases), add(a.cases(k)); end
    if isfield(a,'custom_condition')
        c = a.custom_condition;
        assert(islogical(c.enabled) && isscalar(c.enabled),'SLVT:Case','Custom enabled must be true or false.');
        if c.enabled
            validateattributes(c.wind_speed_mph,{'numeric'},{'scalar','real','finite','nonnegative'});
            validateattributes(c.launch_angle_from_vertical_deg,{'numeric'},{'scalar','real','finite','>=',0,'<',90});
            modes = cellstr(c.payload_deployment); recoveries = cellstr(c.recovery_configuration);
            for i = 1:numel(modes)
                for j = 1:numel(recoveries)
                    item = struct('name',sprintf('%s_%s_%s',c.name,modes{i},recoveries{j}), ...
                        'wind_speed_mph',c.wind_speed_mph, ...
                        'launch_angle_from_vertical_deg',c.launch_angle_from_vertical_deg, ...
                        'recovery_configuration',recoveries{j},'payload_deployment',modes{i});
                    add(item);
                end
            end
        end
    end
    assert(~isempty(cases) && numel(cases)<=2000,'SLVT:Case','Choose 1 to 2000 cases.');
    assert(numel(unique({cases.name}))==numel(cases),'SLVT:Case','Case names must be unique.');
    if isfield(a,'recovery_configuration_ids')
        ids = a.recovery_configuration_ids;
        assert(ids.primary==1 && ids.secondary==2 && ids.tertiary==3, ...
            'SLVT:Case','Recovery mapping must be primary=1, secondary=2, tertiary=3.');
    end
    function add(item)
        if ~isfield(item,'wind_speed_mph'), item.wind_speed_mph = launch.environment.wind_speed_mph; end
        if ~isfield(item,'launch_angle_from_vertical_deg'), item.launch_angle_from_vertical_deg = launch.launch.launch_angle_from_vertical_deg; end
        validateattributes(item.wind_speed_mph,{'numeric'},{'scalar','real','finite','nonnegative'});
        validateattributes(item.launch_angle_from_vertical_deg,{'numeric'},{'scalar','real','finite','>=',0,'<',90});
        assert(ischar(item.name) && ~isempty(item.name),'SLVT:Case','Each case needs a name.');
        assert(any(strcmp(item.payload_deployment,{'deploy','retain'})),'SLVT:Case','Unknown payload case.');
        assert(any(strcmp(item.recovery_configuration,{'primary','secondary','tertiary'})),'SLVT:Case','Unknown recovery configuration.');
        cases(end+1) = struct('name',item.name,'wind_speed_mph',item.wind_speed_mph, ...
            'launch_angle_from_vertical_deg',item.launch_angle_from_vertical_deg, ...
            'recovery_configuration',item.recovery_configuration,'payload_deployment',item.payload_deployment);
    end
end
