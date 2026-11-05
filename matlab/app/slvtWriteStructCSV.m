function slvtWriteStructCSV(filename,rows)
    fid=fopen(filename,'w'); assert(fid>=0,'SLVT:Write','Cannot write CSV.');
    cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
    names=fieldnames(rows); fprintf(fid,'%s\n',strjoin(names,','));
    for i=1:numel(rows)
        cells=cell(1,numel(names));
        for j=1:numel(names)
            x=rows(i).(names{j});
            if isnumeric(x) || islogical(x)
                if isempty(x) || ~isfinite(x), cells{j}=''; else, cells{j}=sprintf('%.15g',x); end
            else
                cells{j}=['"' strrep(char(x),'"','""') '"'];
            end
        end
        fprintf(fid,'%s\n',strjoin(cells,','));
    end
end
