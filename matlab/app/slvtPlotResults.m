function slvtPlotResults(results, caseIndices, quantity, body, showEvents, ax)
%SLVTPLOTRESULTS Draw selected cases into three UI or ordinary axes.
    if isempty(results), return; end
    for k = 1:numel(ax)
        cla(ax(k),'reset'); hold(ax(k),'on'); grid(ax(k),'on');
        ax(k).FontSize = 11; ax(k).Visible = 'on';
    end
    profile = strcmp(quantity,'Flight profile');
    if ~profile
        for k = 2:numel(ax), ax(k).Visible = 'off'; end
    end
    if strcmp(quantity,'Motor thrust')
        plot(ax(1),results.Motor.TimeS,results.Motor.ThrustLbf,'LineWidth',1.8);
        xlabel(ax(1),'Time (s)'); ylabel(ax(1),'Thrust (lbf)');
        title(ax(1),sprintf('Motor | %.3f s burn | %.1f lbf-s impulse', ...
            results.Motor.BurnTimeS,results.Motor.ImpulseLbfS));
        return;
    end
    indices = unique(caseIndices(:)','stable');
    if ~strcmp(quantity,'Drift history')
        [~, keep] = unique([results.Cases(indices).FlightIndex],'stable');
        indices = indices(keep); % duplicate winds have the same vertical curve
    end
    palette = [0.00 0.35 0.65;0.85 0.33 0.05;0.47 0.18 0.60; ...
        0.15 0.55 0.40;0.70 0.20 0.40;0.30 0.45 0.60];
    for n = 1:numel(indices)
        c = results.Cases(indices(n)); f = results.Flights{c.FlightIndex};
        color = palette(mod(n-1,size(palette,1))+1,:);
        datasets = {}; labels = {}; styles = {};
        if any(strcmp(body,{'Vehicle','Both'}))
            datasets{end+1} = f.Vehicle; labels{end+1} = 'vehicle'; styles{end+1} = '-';
        end
        if any(strcmp(body,{'Payload','Both'})) && ~isempty(f.Payload)
            datasets{end+1} = f.Payload; labels{end+1} = 'payload'; styles{end+1} = '--';
        elseif strcmp(body,'Payload') && isempty(f.Payload)
            datasets{end+1} = f.Vehicle; labels{end+1} = 'retained payload (attached)'; styles{end+1} = '--';
        end
        for b = 1:numel(datasets)
            trace = datasets{b};
            label = sprintf('%s R%d %g deg | %s',f.Mode,c.Recovery,c.LaunchAngleDeg,labels{b});
            if strcmp(quantity,'Drift history'), label = sprintf('%s | %g mph',label,c.WindMph); end
            options = {'Color',color,'LineStyle',styles{b},'LineWidth',1.6,'DisplayName',label};
            % Plot reduction only; every stored/exported integration sample remains intact.
            skip = max(1,ceil(size(trace,1)/6000));
            take = unique([1:skip:size(trace,1),size(trace,1)]);
            if profile
                for k = 1:3, plot(ax(k),trace(take,1),trace(take,k+1),options{:}); end
            elseif strcmp(quantity,'Drift vs wind')
                winds = sort(results.Selection.WindsMph(:));
                if numel(winds) == 1, winds = unique([0;winds]); end
                descentTime = trace(end,1)-f.Metrics.TimeToApogeeS;
                plot(ax(1),winds,winds*5280/3600*descentTime,'o',options{:});
            else
                x = trace(take,1);
                switch quantity
                    case 'Altitude', y = trace(take,2);
                    case 'Vertical velocity', y = trace(take,3);
                    case 'Acceleration', y = trace(take,4);
                    case 'Drift history', y = c.WindMph*5280/3600*max(0,x-f.Metrics.TimeToApogeeS);
                    otherwise, error('SLVT:Plot','Unknown plot quantity.');
                end
                plot(ax(1),x,y,options{:});
            end
        end
    end
    if profile
        units = {'Altitude (ft AGL)','Vertical velocity (ft/s)','Acceleration (ft/s^2)'};
        for k = 1:3, ylabel(ax(k),units{k}); xlabel(ax(k),'Time (s)'); end
    else
        xlabel(ax(1),'Time (s)');
        switch quantity
            case 'Altitude', ylabel(ax(1),'Altitude (ft AGL)');
            case 'Vertical velocity', ylabel(ax(1),'Vertical velocity (ft/s)');
            case 'Acceleration', ylabel(ax(1),'Acceleration (ft/s^2)');
            case 'Drift history', ylabel(ax(1),'Drift from apogee (ft)');
            case 'Drift vs wind'
                xlabel(ax(1),'Wind speed (mph)'); ylabel(ax(1),'Touchdown drift from apogee (ft)');
        end
    end
    title(ax(1),quantity,'Interpreter','none');
    if ~isempty(ax(1).Children), legend(ax(1),'show','Location','best','Interpreter','none'); end
    if showEvents && numel(indices) == 1 && ~strcmp(quantity,'Drift vs wind')
        f = results.Flights{results.Cases(indices(1)).FlightIndex};
        key = {'Motor burnout','Apogee','Main fully open (altitude estimate)','Payload release'};
        for e = 1:numel(f.Events)
            event = f.Events(e);
            if ismember(event.Name,key)
                activeAxes = 1;
                if profile, activeAxes = 1:3; end
                for k = activeAxes
                    xline(ax(k),event.TimeS,':','HandleVisibility','off','Color',[0.4 0.4 0.4]);
                end
            end
        end
    end
    for k = 1:numel(ax), hold(ax(k),'off'); end
end
