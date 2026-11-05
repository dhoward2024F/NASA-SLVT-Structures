function report = run_ci(repoRoot,failOnRequirements)
% Headless CI entry point. Reports are written before a requirement-gate error.
    if nargin<1, repoRoot=fileparts(fileparts(mfilename('fullpath'))); end
    if nargin<2, failOnRequirements=true; end
    addpath(fullfile(fileparts(mfilename('fullpath')),'app'));
    report=slvtRunRepository(repoRoot);
    fprintf('%d cases; %d failed checks; %d not evaluated.\n', ...
        report.case_count,report.failed_check_count,report.not_evaluated_count);
    if failOnRequirements && (report.failed_check_count>0 || report.not_evaluated_count>0)
        error('SLVT:Requirements','Model checks failed or are incomplete; see results/matlab/summary.json.');
    end
end
