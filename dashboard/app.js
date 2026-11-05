'use strict';
const $ = id => document.getElementById(id);
const hosted = document.body.dataset.hosting === 'pages';
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const finite = x => typeof x === 'number' && Number.isFinite(x);
const fmt = (x, places=0) => finite(x) ? x.toLocaleString(undefined,{minimumFractionDigits:places,maximumFractionDigits:places}) : '—';
const label = source => source === 'matlab' ? 'MATLAB model' : 'OpenRocket';
const badge = (text,type='neutral') => `<span class="pill ${type}">${escapeHTML(text)}</span>`;
let data = null, currentView = 'overview';
const filterIds = ['sourceFilter','payloadFilter','recoveryFilter','angleFilter','windFilter'];
function sources() { return $('sourceFilter').value === 'all' ? ['matlab','openrocket'] : [$('sourceFilter').value]; }
function selected(c) {
  return ($('payloadFilter').value==='all'||c.payload_deployment===$('payloadFilter').value) &&
    ($('recoveryFilter').value==='all'||c.recovery_configuration===$('recoveryFilter').value) &&
    ($('angleFilter').value==='all'||c.launch_angle_from_vertical_deg===Number($('angleFilter').value)) &&
    ($('windFilter').value==='all'||c.wind_speed_mph===Number($('windFilter').value));
}
function definitions(){return data.case_definitions.filter(selected);}
function rows() { return sources().flatMap(source=>data.models[source].cases.filter(selected).map(c=>({...c,source}))); }
function checksFor(rid, source) {
  const names=new Set(definitions().map(c=>c.name));
  return data.models[source].requirements.filter(c=>c.requirement_id===rid&&names.has(c.case_name));
}
function reqStatus(rid) {
  const available=sources().filter(s=>data.models[s].coverage.includes(rid));
  if(!available.length||!definitions().length) return ['No coverage','neutral'];
  let count=0,fail=0,unknown=false,stale=false;
  for(const source of available){
    const m=data.models[source], checks=checksFor(rid,source);
    count+=checks.length;fail+=checks.filter(c=>c.status==='fail').length;
    unknown ||= m.status!=='complete' && m.status!=='stale';
    stale ||= m.status==='stale';
    unknown ||= new Set(checks.map(c=>c.case_name)).size < definitions().length || checks.some(c=>c.status==='not_evaluated');
  }
  if(stale) return ['Outdated','neutral'];
  if(unknown||!count) return ['Incomplete','neutral'];
  return fail ? [`${fail} failed`,'fail'] : ['Pass','pass'];
}
function caseStatus(c) {
  const m=data.models[c.source];
  if(m.status!=='complete') return [m.status==='stale'?'Outdated':m.status,'neutral'];
  const checks=m.requirements.filter(x=>x.case_name===c.case_name);
  if(c.run_status!=='ok') return ['Run error','fail'];
  if(!checks.length || checks.some(x=>x.status==='not_evaluated'))return ['Incomplete','neutral'];
  const n=checks.filter(x=>x.status==='fail').length;
  return n ? [`${n} failed`,'fail'] : [c.source==='openrocket'?'Ascent pass':'Pass','pass'];
}
function limit(r) { return r.type==='range'?`${fmt(r.minimum)}–${fmt(r.maximum)} ${r.units}` : `${r.type==='minimum'?'≥':'≤'} ${fmt(r.value,r.value<5?1:0)} ${r.units}`; }
function modelState(m) {return m.status==='complete'?badge('Current','pass'):badge(({missing:'No results',error:'Run failed',stale:'Outdated',incomplete:'Incomplete',skipped:'Not run'})[m.status]||m.status,'neutral');}
function selectView(view){
  currentView=view;
  for(const el of document.querySelectorAll('.view'))el.hidden=el.id!==view;
  for(const el of document.querySelectorAll('.nav'))el.classList.toggle('active',el.dataset.view===view);
  $('pageTitle').textContent=({overview:'Mission overview',cases:'Analysis cases',requirements:'Requirement traceability',notes:'Models & assumptions'})[view];
}
function fillOptions(id, values, unit, all){
  const previous=$(id).value;
  $(id).innerHTML=`<option value="all">${all}</option>`+values.map(v=>`<option value="${v}">${v} ${unit}</option>`).join('');
  $(id).value=values.map(String).includes(previous)?previous:'all';
}
function renderHeader(){
  $('vehicle').textContent=data.vehicle;
  const complete=data.status==='complete';
  $('freshness').className=`pill ${complete?'pass':'neutral'}`;
  $('freshness').textContent=complete?(hosted?'PUBLISHED ANALYSIS':'CURRENT INPUTS'):'CHECK RESULT COVERAGE';
  $('sources').innerHTML=['matlab','openrocket'].map(s=>`<div class="source"><div><strong>${label(s)}</strong><small>${s==='matlab'?'All payload and recovery cases':'Ascent reference · shared across recovery cases'}</small></div>${modelState(data.models[s])}</div>`).join('');
  const provenance=['matlab','openrocket'].map(s=>data.models[s].provenance).filter(Boolean);
  $('commit').textContent=provenance.length? [...new Set(provenance.map(p=>(p.git_commit||'local').slice(0,10)))].join(' / '):'No run recorded';
  $('runTime').textContent=provenance.length ? provenance.map(p=>new Date(p.created_at)).filter(d=>!Number.isNaN(d.valueOf())).sort((a,b)=>b-a)[0]?.toLocaleString()||'Timestamp unavailable':'Run analysis or download CI results';
  const issues=[];
  for(const s of ['matlab','openrocket']){
    const m=data.models[s];
    if(m.status==='missing')issues.push(hosted?`${label(s)}: no results in this published run. Inspect the GitHub Actions run.`:`${label(s)}: no local results. Run python scripts/sync_results.py or python scripts/run_analysis.py.`);
    if(m.status==='stale')issues.push(hosted?`${label(s)}: results did not match the analyzed inputs at publication. Rerun the analysis workflow.`:`${label(s)}: these results do not match the current local model/config files. Run analysis again or pull the matching commit.`);
    if(m.status==='error'||m.status==='skipped'||m.status==='incomplete')issues.push(`${label(s)}: ${m.error||'analysis incomplete; inspect results/'+s+'/run.log'}`);
  }
  if(hosted){
    const repo=data.publication?.repository;
    if(typeof repo==='string'&&/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)){
      $('repositoryLink').href=`https://github.com/${repo}`;
      const run=data.publication?.workflow_run_id;
      $('workflowLink').href=typeof run==='string'&&/^\d+$/.test(run)?`https://github.com/${repo}/actions/runs/${run}`:`https://github.com/${repo}/actions`;
    }
  }
  issues.push(...(data.errors||[]));
  $('banner').hidden=!issues.length;$('banner').textContent=issues.join('\n');
}
function renderMetrics(){
  const rr=rows();
  const vals=key=>rr.map(x=>x[key]).filter(finite);
  const ap=vals('apogee_ft'), rail=vals('rail_exit_velocity_fps'),mach=vals('max_mach'),ke=vals('max_landing_kinetic_energy_ft_lbf');
  const get=id=>data.requirement_definitions.find(r=>r.id===id);
  const cards=[['Apogee envelope',ap.length?`${fmt(Math.min(...ap))}–${fmt(Math.max(...ap))}`:'—','ft AGL','2.1',ap.length&&(Math.min(...ap)<get('2.1').minimum||Math.max(...ap)>get('2.1').maximum)],
    ['Minimum rail exit',rail.length?fmt(Math.min(...rail),1):'—','ft/s','2.14',rail.length&&Math.min(...rail)<get('2.14').value],
    ['Maximum Mach',mach.length?fmt(Math.max(...mach),3):'—','Mach','2.20.6',mach.length&&Math.max(...mach)>get('2.20.6').value],
    ['Maximum section landing energy',ke.length?fmt(Math.max(...ke),1):'—','ft-lbf','3.2',ke.length&&Math.max(...ke)>get('3.2').value]];
  $('metrics').innerHTML=cards.map(([title,value,unit,id,bad])=>`<article class="metric"><h3>${title}</h3><div class="value">${value}<small>${unit}</small></div><p>${get(id)?escapeHTML(limit(get(id))):'Limit unavailable'} · Req. ${id}</p><div class="rule ${bad?'bad':''}"></div></article>`).join('');
}
function renderChart(){
  const rr=rows().filter(c=>finite(c.apogee_ft));
  if(!rr.length){$('chart').innerHTML='<div class="empty">No simulation results yet.<code>python scripts/run_analysis.py</code>Committed model results will appear here after analysis.</div>';$('chartLegend').innerHTML='';return;}
  const groups=new Map();
  for(const c of rr){const key=`${c.source}|${c.launch_angle_from_vertical_deg}`;if(!groups.has(key))groups.set(key,{source:c.source,angle:c.launch_angle_from_vertical_deg,points:new Map()});groups.get(key).points.set(c.wind_speed_mph,c.apogee_ft);}
  const width=650,height=285,left=57,right=20,top=20,bottom=38;
  const req=data.requirement_definitions.find(r=>r.id==='2.1')||{minimum:4000,maximum:6000};
  const yy=rr.map(c=>c.apogee_ft),xx=rr.map(c=>c.wind_speed_mph);
  const ymin=Math.floor(Math.min(req.minimum*.85,...yy)/500)*500,ymax=Math.ceil(Math.max(req.maximum*1.1,...yy)/500)*500;
  const xmin=Math.min(0,...xx),xmax=Math.max(20,...xx);
  const x=v=>left+(v-xmin)/(xmax-xmin||1)*(width-left-right),y=v=>top+(ymax-v)/(ymax-ymin||1)*(height-top-bottom);
  let svg=`<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Apogee versus wind, with NASA target band"><rect x="${left}" y="${y(req.maximum)}" width="${width-left-right}" height="${y(req.minimum)-y(req.maximum)}" fill="#edf4f7"/><text x="${width-right-4}" y="${y(req.maximum)+14}" text-anchor="end" fill="#7b929f" font-size="9">REQUIREMENT BAND</text>`;
  for(let i=0;i<=4;i++){const val=ymin+(ymax-ymin)*i/4;svg+=`<line x1="${left}" x2="${width-right}" y1="${y(val)}" y2="${y(val)}" stroke="#e3e9ed"/><text x="${left-10}" y="${y(val)+4}" text-anchor="end" fill="#72818b" font-size="10">${fmt(val)}</text>`;}
  const ticks=[...new Set([0,5,10,15,20,...xx])].sort((a,b)=>a-b);
  for(const val of ticks)svg+=`<text x="${x(val)}" y="${height-20}" text-anchor="middle" fill="#72818b" font-size="10">${val}</text>`;
  svg+=`<text x="${(width+left)/2}" y="${height-2}" text-anchor="middle" fill="#72818b" font-size="10">Wind speed (mph)</text>`;
  const colors={matlab:'#146f9b',openrocket:'#8b3f55'};
  $('chartLegend').innerHTML=[...groups.values()].map(g=>`<span><i class="${g.source}"></i>${label(g.source)} · ${g.angle}°</span>`).join('');
  for(const g of groups.values()){
    const points=[...g.points].sort((a,b)=>a[0]-b[0]);
    svg+=`<polyline points="${points.map(([a,b])=>`${x(a)},${y(b)}`).join(' ')}" stroke="${colors[g.source]}" stroke-width="2.2" fill="none" ${g.angle===5?'':'stroke-dasharray="6 5"'}/>`;
    for(const [a,b] of points)svg+=`<circle cx="${x(a)}" cy="${y(b)}" r="3.4" fill="white" stroke="${colors[g.source]}" stroke-width="2"><title>${label(g.source)} · ${g.angle}° · ${a} mph: ${fmt(b)} ft</title></circle>`;
  }
  $('chart').innerHTML=svg+'</svg>';
}
function renderRequirements(){
  $('checkSummary').innerHTML=data.requirement_definitions.map(r=>{const [text,type]=reqStatus(r.id);return `<div class="req-item"><div><strong>${r.id}</strong>${escapeHTML(({ '2.1':'Apogee','2.12':'Thrust-to-weight','2.14':'Rail exit velocity','2.20.6':'Mach limit','3.2':'Section landing energy','3.10':'Landing drift','3.11':'Descent time'})[r.id]||r.name)}</div>${badge(text,type)}</div>`;}).join('');
  $('reqRows').innerHTML=data.requirement_definitions.flatMap(r=>sources().map(s=>{
    const m=data.models[s],covered=m.coverage.includes(r.id),checks=checksFor(r.id,s);
    const pass=checks.filter(c=>c.status==='pass').length,fail=checks.filter(c=>c.status==='fail').length;
    const missing=checks.filter(c=>c.status==='not_evaluated').length+Math.max(0,definitions().length-new Set(checks.map(c=>c.case_name)).size);
    const state=!covered?['Not covered','neutral']:m.status!=='complete'?[m.status==='stale'?'Outdated':'Incomplete','neutral']:missing?['Incomplete','neutral']:fail?['Fail','fail']:checks.length?['Pass','pass']:['No cases','neutral'];
    return `<tr><td>${r.id} · ${escapeHTML(r.name)}<small>${escapeHTML(r.scope.replaceAll('_',' '))}</small></td><td>${escapeHTML(limit(r))}</td><td>${label(s)}</td><td>${covered?pass:'—'}</td><td>${covered?fail:'—'}</td><td>${covered?missing:'—'}</td><td>${badge(...state)}</td></tr>`;
  })).join('');
}
function visibleRows(){const term=$('search').value.trim().toLowerCase();return rows().filter(c=>!term||c.case_name.toLowerCase().includes(term));}
function renderCases(){
  const rr=visibleRows(),term=$('search').value.trim().toLowerCase();
  const count=definitions().filter(c=>!term||c.name.toLowerCase().includes(term)).length;
  $('caseCount').textContent=`${count} conditions · ${rr.length} model results`;
  $('caseRows').innerHTML=rr.length?rr.map(c=>`<tr data-case="${escapeHTML(c.case_name)}" tabindex="0" aria-label="Inspect ${escapeHTML(c.case_name)}"><td>${escapeHTML(c.case_name)}<small>${label(c.source)}${c.source==='openrocket'?' · shared ascent':''}</small></td><td>${escapeHTML(c.payload_deployment)}</td><td>${escapeHTML(c.recovery_configuration)}</td><td>${c.launch_angle_from_vertical_deg}°</td><td>${c.wind_speed_mph} mph</td><td>${fmt(c.apogee_ft)}</td><td>${fmt(c.rail_exit_velocity_fps,1)}</td><td>${fmt(c.max_mach,3)}</td><td>${fmt(c.descent_time_s,1)}</td><td>${badge(...caseStatus(c))}</td></tr>`).join(''):'<tr><td colspan="10" class="empty">No matching results. Adjust filters or run the models.</td></tr>';
  for(const row of $('caseRows').querySelectorAll('[data-case]')){
    const open=()=>{selectView('overview');$('casePicker').value=row.dataset.case;renderDetail();$('caseDetail').scrollIntoView({behavior:'smooth',block:'center'});};
    row.addEventListener('click',open);row.addEventListener('keydown',e=>{if(e.key==='Enter')open();});
  }
  $('export').disabled=!rr.length;
}
function renderDetail(){
  const name=$('casePicker').value;
  const models=['matlab','openrocket'];
  const selectedRows=models.map(s=>data.models[s].cases.find(c=>c.case_name===name));
  if(!name){$('caseDetail').innerHTML='<p class="empty">No cases match these filters.</p>';return;}
  const metrics=[['Apogee (ft AGL)','apogee_ft',0],['Rail exit speed (ft/s)','rail_exit_velocity_fps',1],['Max Mach','max_mach',3],['Average thrust-to-weight','thrust_to_weight_ratio',2],['Longest descent (s)','descent_time_s',1],['Max landing drift (ft)','landing_drift_ft',0]];
  const sections=data.models.matlab.sections.filter(s=>s.case_name===name);
  $('caseDetail').innerHTML=`<div class="detail-grid"><div><h3>Model comparison</h3><div class="table-wrap"><table><thead><tr><th>Metric</th><th>MATLAB</th><th>OpenRocket</th></tr></thead><tbody>${metrics.map(([title,key,n])=>`<tr><td>${title}</td>${selectedRows.map(row=>`<td>${fmt(row?.[key],n)}</td>`).join('')}</tr>`).join('')}</tbody></table></div><p class="caption">OpenRocket is an ascent reference. Values reflect each model’s own geometry, mass and assumptions.</p></div><div><h3>Landing sections · MATLAB model</h3>${sections.length?sections.map(s=>`<div class="section-row"><div>${escapeHTML(s.name)}<small>${fmt(s.landing_mass_lbm,2)} lbm · ${fmt(s.impact_velocity_fps,1)} ft/s impact</small></div><div class="section-values">${fmt(s.landing_kinetic_energy_ft_lbf,1)} ft-lbf<small>${fmt(s.landing_drift_ft)} ft drift · ${fmt(s.descent_time_s,1)} s</small></div></div>`).join(''):'<p class="empty">Section results are not available for this case.</p>'}</div></div>`;
}
function renderNotes(){
  $('modelNotes').innerHTML=['matlab','openrocket'].map(s=>{
    const m=data.models[s],prov=m.provenance||{};
    return `<article class="panel"><div class="panel-title"><div><p class="eyebrow">${s==='matlab'?'RECOVERY & VERTICAL FLIGHT':'3D ASCENT REFERENCE'}</p><h2>${label(s)}</h2></div>${modelState(m)}</div><p class="caption">Runtime: ${escapeHTML(prov.runtime||'Not recorded')} · Commit: ${escapeHTML(prov.git_commit||'Not recorded')}</p><ul class="note-list">${m.notes.map(n=>`<li>${escapeHTML(n)}</li>`).join('')||'<li>No model report available yet.</li>'}</ul>${m.error?`<p class="banner">${escapeHTML(m.error)}</p>`:''}</article>`;
  }).join('');
}
function render(){
  if(!data)return;
  renderHeader();renderMetrics();renderChart();renderRequirements();renderCases();renderNotes();
  const old=$('casePicker').value;
  $('casePicker').innerHTML=definitions().map(c=>`<option value="${escapeHTML(c.name)}">${escapeHTML(c.name)}</option>`).join('');
  if(definitions().some(c=>c.name===old))$('casePicker').value=old;
  renderDetail();
}
async function refresh(){
  $('refresh').disabled=true;
  try{
    let response=await fetch(hosted?'data.json':'api/dashboard',{cache:'no-store'});
    // A static preview can also use the packaged data file.
    if(!hosted&&(response.status===404||(response.ok&&(response.headers.get('content-type')||'').includes('text/html'))))response=await fetch('data.json',{cache:'no-store'});
    if(!response.ok)throw new Error(`Cannot load results (${response.status}). ${hosted?'Refresh after the Pages deployment completes.':'Reopen the URL printed by serve_dashboard.py.'}`);
    const next=await response.json();if(next.schema_version!==1)throw new Error('Unsupported dashboard data version');
    data=next;
    fillOptions('angleFilter',[...new Set(data.case_definitions.map(c=>c.launch_angle_from_vertical_deg))].sort((a,b)=>a-b),'°','All angles');
    fillOptions('windFilter',[...new Set(data.case_definitions.map(c=>c.wind_speed_mph))].sort((a,b)=>a-b),'mph','All winds');
    render();
  }catch(error){$('banner').hidden=false;$('banner').textContent=error.message;$('freshness').textContent='LOAD ERROR';$('freshness').className='pill fail';}
  finally{$('refresh').disabled=false;}
}
if(hosted){
  $('hostingLabel').textContent='GITHUB PAGES';
  $('hostingDescription').textContent='Published mission results. Updated by GitHub Actions.';
  $('localInstructions').hidden=true;
  $('pagesInstructions').hidden=false;
}
for(const el of document.querySelectorAll('.nav'))el.addEventListener('click',()=>selectView(el.dataset.view));
for(const id of filterIds)$(id).addEventListener('change',render);
$('reset').addEventListener('click',()=>{filterIds.forEach(id=>$(id).value='all');$('search').value='';render();});
$('refresh').addEventListener('click',refresh);$('casePicker').addEventListener('change',renderDetail);$('search').addEventListener('input',renderCases);
$('export').addEventListener('click',()=>{
  const rr=visibleRows(),columns=['source','case_name','payload_deployment','recovery_configuration','launch_angle_from_vertical_deg','wind_speed_mph','apogee_ft','rail_exit_velocity_fps','max_mach','descent_time_s','landing_drift_ft','max_landing_kinetic_energy_ft_lbf'];
  const quote=v=>'"'+String(v??'').replace(/^[=+@-]/,"'$&").replaceAll('"','""')+'"';
  const csv=[columns.join(','),...rr.map(c=>columns.map(k=>quote(c[k])).join(','))].join('\r\n');
  const url=URL.createObjectURL(new Blob([csv],{type:'text/csv'}));const a=document.createElement('a');a.href=url;a.download='slvt-filtered-cases.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
refresh();setInterval(refresh,30000);
