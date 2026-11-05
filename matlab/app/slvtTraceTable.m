function output = slvtTraceTable(trace, apogeeTimeS, windMph)
%SLVTTRACETABLE Time histories with physically consistent post-apogee drift.
    output = array2table(trace,'VariableNames',{'TimeS','AltitudeFt', ...
        'VerticalVelocityFtS','AccelerationFtS2','SuspendedMassLbm','PhaseCode'});
    output.DriftFt = windMph*5280/3600*max(0,output.TimeS-apogeeTimeS);
end
