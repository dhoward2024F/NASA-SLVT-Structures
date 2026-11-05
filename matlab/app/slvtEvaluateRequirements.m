function checks = slvtEvaluateRequirements(requirements,metrics,sections,caseName)
% Inclusive bounds. Unsupported/missing metrics never pass.
    checks = struct('case_name',{},'requirement_id',{},'section',{}, ...
        'metric',{},'value',{},'status',{},'units',{});
    for k=1:numel(requirements)
        if iscell(requirements), r=requirements{k}; else, r=requirements(k); end
        if strcmp(r.scope,'each_independent_section')
            if isempty(sections), append(r,'unavailable',NaN); end
            for j=1:numel(sections)
                value=NaN;
                if isfield(sections(j),r.metric), value=sections(j).(r.metric); end
                append(r,sections(j).name,value);
            end
        else
            value=NaN;
            if isfield(metrics,r.metric), value=metrics.(r.metric); end
            append(r,'launch_vehicle',value);
        end
    end
    function append(r,section,value)
        status='not_evaluated';
        if isnumeric(value) && isscalar(value) && isfinite(value)
            switch r.type
                case 'range', pass=value>=r.minimum && value<=r.maximum;
                case 'minimum', pass=value>=r.value;
                case 'maximum', pass=value<=r.value;
                otherwise, error('SLVT:Requirement','Unknown comparison type: %s.',r.type);
            end
            if pass, status='pass'; else, status='fail'; end
        end
        checks(end+1)=struct('case_name',caseName,'requirement_id',r.id, ...
            'section',section,'metric',r.metric,'value',value,'status',status,'units',r.units);
    end
end
