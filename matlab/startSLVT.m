function app = startSLVT()
% Start the standalone GUI without importing repository inputs automatically.
    root=fileparts(mfilename('fullpath'));
    addpath(fullfile(root,'app'));
    app=SLVTFlightApp();
end
