function slvtWriteJSON(filename, value)
% Atomic JSON write. NaN metrics become JSON null.
    folder = fileparts(filename);
    if ~exist(folder,'dir'), mkdir(folder); end
    temporary = [tempname(folder) '.json'];
    fid = fopen(temporary,'w');
    assert(fid >= 0,'SLVT:Write','Cannot write %s.',filename);
    try
        fprintf(fid,'%s\n',jsonencode(value)); fclose(fid);
        [ok,msg] = movefile(temporary,filename,'f');
        assert(ok,'SLVT:Write','%s',msg);
    catch problem
        if any(fopen('all') == fid), fclose(fid); end
        if exist(temporary,'file'), delete(temporary); end
        rethrow(problem);
    end
end
