function sections = slvtSectionData(flight,cfg)
% Shared section masses and landing KE for GUI tables and repository reports.
    s = flight.Metrics;
    deploying = strcmp(flight.Mode, 'Deploy');
    excluded = double(cfg.excludeHardwareMass);
    if deploying
        labels = {'Payload and nosecone';'Forward section';'Central section';'Aft section'};
        liftoff = [cfg.payloadMassLbm;cfg.forwardMassLbm;cfg.centralMassLbm;cfg.aftMassLbm];
        burnout = liftoff - [0;0;0;cfg.propellantMassLbm];
        drogue = burnout - excluded*[0;0;0;cfg.drogueHardwareLbm];
        landing = drogue - excluded*[cfg.payloadHardwareLbm;0;cfg.mainHardwareLbm;0];
        speed = [s.PayloadImpactVelocityFtS;repmat(s.VehicleImpactVelocityFtS,3,1)];
    else
        labels = {'Forward + retained payload/nosecone';'Central section';'Aft section'};
        liftoff = [cfg.forwardMassLbm + cfg.payloadMassLbm;cfg.centralMassLbm;cfg.aftMassLbm];
        burnout = liftoff - [0;0;cfg.propellantMassLbm];
        drogue = burnout - excluded*[0;0;cfg.drogueHardwareLbm];
        landing = drogue - excluded*[0;cfg.mainHardwareLbm;0];
        speed = repmat(s.VehicleImpactVelocityFtS,3,1);
    end
    drogueRate = repmat(s.DrogueTerminalEstimateFtS,numel(labels),1);
    drogueKE = 0.5*(drogue/cfg.g).*drogueRate.^2;
    landingKE = 0.5*(landing/cfg.g).*speed.^2;

    sections = struct('Section',{},'LiftoffMassLbm',{},'BurnoutMassLbm',{}, ...
        'DrogueMassLbm',{},'LandingMassLbm',{},'DrogueRateFtS',{}, ...
        'DrogueKEFtLbf',{},'ImpactVelocityFtS',{},'ImpactKEFtLbf',{});
    for k=1:numel(labels)
        sections(k) = struct('Section',labels{k},'LiftoffMassLbm',liftoff(k), ...
            'BurnoutMassLbm',burnout(k),'DrogueMassLbm',drogue(k), ...
            'LandingMassLbm',landing(k),'DrogueRateFtS',drogueRate(k), ...
            'DrogueKEFtLbf',drogueKE(k),'ImpactVelocityFtS',speed(k),'ImpactKEFtLbf',landingKE(k));
    end
end
