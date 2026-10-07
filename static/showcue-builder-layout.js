/* Compact preparation UI. Existing source rows, handlers and save pipeline remain authoritative. */
(function(root){
'use strict';
const batchFields=new Set(['phase','section','type','foh','ret','plt','lum']);
function patchCues(cues,ids,patch){
 for(const field of Object.keys(patch))if(!batchFields.has(field))throw Error('Champ batch non autorisé : '+field);
 const selected=new Set(ids);return cues.map(c=>selected.has(c.id)?{...c,...patch}:c);
}
function moveGroup(cues,ids,target,position){
 const selected=new Set(ids),group=cues.filter(c=>selected.has(c.id)),rest=cues.filter(c=>!selected.has(c.id));
 if(position==='start')return [...group,...rest];if(position==='end')return [...rest,...group];
 if(selected.has(target))return [...cues];
 const index=rest.findIndex(c=>c.id===target);if(index<0)return [...cues];
 rest.splice(index+(position==='after'?1:0),0,...group);return rest;
}
function selectIds(visible,current,id,anchor,event,checkbox=false){
 const selected=new Set(current);
 if(event.shiftKey&&visible.includes(anchor)&&visible.includes(id)){
  const a=visible.indexOf(anchor),b=visible.indexOf(id);if(!event.ctrlKey&&!event.metaKey)selected.clear();
  visible.slice(Math.min(a,b),Math.max(a,b)+1).forEach(v=>selected.add(v));
 }else if(checkbox||event.ctrlKey||event.metaKey){selected.has(id)?selected.delete(id):selected.add(id);}
 else{selected.clear();selected.add(id);}
 return [...selected];
}
if(typeof module!=='undefined'&&module.exports){module.exports={patchCues,moveGroup,selectIds};return;}
function install(){
 const $=id=>document.getElementById(id),header=document.querySelector('header.top'),source=$('cues'),host=$('cue-consultation');
 if(!header||!source||!host||document.body.classList.contains('cl-builder-compact'))return;
 document.body.classList.add('cl-builder-compact');
 const local=document.querySelector('main.shell').dataset.builderLocal==='true';
 const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
 const button=(text,fn)=>{const n=el('button',text);n.type='button';n.onclick=fn;return n;};
 const toolbar=$('cue-v2-toolbar'),bar=header.querySelector('.bar');
 // Move the original session manager, preserving IDs, file input and handlers.
 const sessions=header.querySelector('.cl-session-panel');
 if(sessions){
  const dialog=el('dialog',null,'ce-dialog cl-sessions-dialog');dialog.id='cl-builder-sessions-dialog';
  const title=el('header',null,'ce-panel-header');title.append(el('h2','Gérer les sessions'),button('Fermer',()=>dialog.close()));
  sessions.open=true;dialog.append(title,sessions);document.body.append(dialog);
  const open=button('GÉRER LES SESSIONS',()=>dialog.showModal());open.id='cl-builder-sessions-open';bar.append(open);
 }
 // Original organisation controls become one menu, never recreated as business logic.
 const organization=[...document.querySelectorAll('.filters')].find(n=>n.querySelector('strong')?.textContent==='TRIER / ORGANISER');
 if(organization&&toolbar){
  const menu=el('details',null,'cue-v2-menu');menu.id='cl-builder-organize-menu';menu.append(el('summary','ORGANISER'));
  const panel=el('div',null,'cue-v2-menu-panel');for(const b of [...organization.querySelectorAll('button')])panel.append(b);
  menu.append(panel);const importer=[...toolbar.querySelectorAll('details')].find(n=>n.querySelector('summary')?.textContent==='IMPORTER');
  importer?.after(menu);if(!menu.parentNode)toolbar.append(menu);organization.remove();
 }
 const filters=$('filter-phase')?.closest('.filters');if(filters){filters.classList.add('cl-builder-filters');header.append(filters);}
 const access=$('builder-access-mode');if(access){access.textContent=local?'MODE LOCAL':'CONSULTATION DISTANTE — modifications sur le poste local';bar.append(access);}
 // Keep detailed validation available without filling the sticky header.
 const diagnostics=el('details',null,'cl-builder-diagnostics');diagnostics.append(el('summary','État / validation du Builder'));
 for(const id of ['builder-save-help','builder-recovery','summary'])if($(id))diagnostics.append($(id));
 header.after(diagnostics);
 if($('builder-bulk-role-bar'))$('builder-bulk-role-bar').classList.add('cl-legacy-bulk');
 const showcue=toolbar?.querySelector('.cue-v2-showcue');if(showcue){
  const buttons=[...showcue.querySelectorAll('button')];if(buttons[0]){buttons[0].title=buttons[0].textContent;buttons[0].textContent='PRÉVISUALISER';}if(buttons[1]){buttons[1].title=buttons[1].textContent;buttons[1].textContent='METTRE À JOUR';}
 }
 // The import report retains its adoption/save controls, and can be folded.
 const feedback=$('cl-builder-import-feedback');if(feedback){
  const close=button('Réduire',()=>{feedback.classList.toggle('cl-feedback-reduced');close.textContent=feedback.classList.contains('cl-feedback-reduced')?'Développer':'Réduire';});
  close.className='cl-feedback-toggle';feedback.append(close);header.after(feedback);
 }
 toolbar?.addEventListener('toggle',event=>{const target=event.target;if(target.open)for(const d of toolbar.querySelectorAll('details.cue-v2-menu'))if(d!==target)d.open=false;},true);
 const selectionBar=el('div',null,'cl-builder-batch');selectionBar.id='cl-builder-batch';selectionBar.hidden=true;host.before(selectionBar);
 const count=el('strong'),field=el('select'),value=el('select');field.setAttribute('aria-label','Champ à modifier en masse');value.setAttribute('aria-label','Nouvelle valeur du groupe');
 for(const [key,name] of [['phase','PHASE'],['section','SECTION'],['type','TYPE']])field.add(new Option(name,key));
 const apply=button('Appliquer',()=>applyPatch({[field.value]:value.value}));apply.className='primary';
 const destinations=el('details',null,'cl-batch-destinations');destinations.append(el('summary','DESTINATIONS'));
 const postFields={};
 for(const [key,name] of [['foh','FOH'],['ret','RET'],['plt','PLT'],['lum','LUM']]){
  const label=el('label',name),check=el('input');check.type='checkbox';check.onchange=()=>check.dataset.touched='true';label.prepend(check);destinations.append(label);postFields[key]=check;
 }
 destinations.append(button('Appliquer destinations',()=>{
  const patch={};for(const [key,check] of Object.entries(postFields))if(check.dataset.touched==='true')patch[key]=check.checked;
  if(Object.keys(patch).length)applyPatch(patch);
 }));
 const target=el('select');target.setAttribute('aria-label','Cue de destination du déplacement');
 const position=el('select');position.setAttribute('aria-label','Position du groupe');for(const [key,name] of [['before','Avant'],['after','Après'],['start','Au début'],['end','À la fin']])position.add(new Option(name,key));
 const move=button('Déplacer',()=>{
  if(!local)return;const rows=[...source.rows],ids=selectedIds();
  moveGroup(rows.map(r=>({id:r.dataset.id,row:r})),ids,target.value,position.value).forEach(c=>source.append(c.row));changed();
 });
 const remove=button('Supprimer',()=>{const ids=selectedIds();if(!local||!ids.length||!confirm('Supprimer les '+ids.length+' cues sélectionnés ?'))return;for(const r of [...source.rows])if(ids.includes(r.dataset.id))r.remove();changed();});remove.className='danger';
 selectionBar.append(count,field,value,apply,destinations,position,target,move,remove,button('Désélectionner',()=>setSelection([])));
 const legacyRoles=$('builder-bulk-role-bar');if(legacyRoles){const roles=el('details',null,'cl-batch-roles');roles.append(el('summary','RÔLES'),legacyRoles);selectionBar.append(roles);legacyRoles.addEventListener('click',()=>root.CLBuilderRefresh?.());}
 let anchor=null;
 function selectedIds(){return [...source.rows].filter(r=>r.querySelector('.builder-bulk-cue-check')?.checked).map(r=>r.dataset.id);}
 function readField(row,key){const n=row.querySelector('[data-key="'+key+'"]');return n?.matches('input[type="checkbox"]')?n.checked:n?.matches('select,input,textarea')?n.value:n?.textContent||'';}
 function setSelection(ids){const set=new Set(ids);for(const r of source.rows){const n=r.querySelector('.builder-bulk-cue-check');if(n&&n.checked!==set.has(r.dataset.id)){n.checked=set.has(r.dataset.id);n.dispatchEvent(new Event('change',{bubbles:true}));}}root.CLBuilderRefresh?.();}
 function refreshValues(){
  const rows=[...source.rows],selected=rows.filter(r=>selectedIds().includes(r.dataset.id)),values=selected.map(r=>readField(r,field.value));
  const mixed=new Set(values).size>1,current=mixed?'':values[0]||'';
  const presets=field.value==='phase'?['PRESHOW','ENTRACTE','SHOW','FIN']:field.value==='section'?['PRESHOW','ENTRACTE','SHOW','FIN']:[];
  const options=[...new Set([...presets,...rows.map(r=>readField(r,field.value)),...($('filter-'+field.value)?.options||[])].map(v=>typeof v==='string'?v:v.value).filter(Boolean))];
  value.replaceChildren(new Option(mixed?'— valeurs multiples —':'— choisir une valeur —',''));for(const v of options)value.add(new Option(v,v));value.value=current;apply.disabled=!local||!value.value;
 }
 field.onchange=refreshValues;value.onchange=()=>apply.disabled=!local||!value.value;
 function applyPatch(patch){
  if(!local||Object.values(patch).some(v=>v===''))return;
  for(const row of source.rows){if(!selectedIds().includes(row.dataset.id))continue;
   for(const [key,v] of Object.entries(patch)){const n=row.querySelector('[data-key="'+key+'"]');if(!n)continue;
    if(typeof v==='boolean')n.checked=v;else if(n.matches('select')){if(![...n.options].some(o=>o.value===v))n.add(new Option(v,v));n.value=v;}else if(n.matches('input,textarea'))n.value=v;else n.textContent=v;
   }
  }changed();
 }
 function changed(){source.dispatchEvent(new Event('change',{bubbles:true}));root.CLBuilderRefresh?.();}
 root.CLBuilderSelection={
  select(id,event,checkbox){if(!local)return;const visible=[...source.rows].filter(r=>!r.hidden).map(r=>r.dataset.id);setSelection(selectIds(visible,selectedIds(),id,anchor,event,checkbox));if(!event.shiftKey)anchor=id;},
  refresh(){
   const ids=selectedIds();selectionBar.hidden=!ids.length;count.textContent=ids.length+' CUES SÉLECTIONNÉS';if($('builder-bulk-role-count'))$('builder-bulk-role-count').textContent=ids.length+' cues sélectionnés';
   for(const r of host.querySelectorAll('.ce-cue')){const selected=ids.includes(r.dataset.cueId);r.classList.toggle('cl-cue-selected',selected);r.setAttribute('aria-selected',String(selected));}
   refreshValues();target.replaceChildren();for(const row of source.rows)if(!ids.includes(row.dataset.id))target.add(new Option(readField(row,'number')+' · '+readField(row,'text').slice(0,48),row.dataset.id));
   for(const [key,check] of Object.entries(postFields)){const states=[...source.rows].filter(r=>ids.includes(r.dataset.id)).map(r=>readField(r,key));check.indeterminate=new Set(states).size>1;check.checked=states.length>0&&states.every(Boolean);delete check.dataset.touched;}
  }
 };
 // Reserve a compact column for row actions, with explicit accessible labels.
 function compactRows(){
  for(const row of host.querySelectorAll('.ce-cue')){
   const actions=row.querySelector('.ce-row-actions');if(!actions)continue;
   // Move controls added by the organisation module into the same actions cell.
   for(const move of row.querySelectorAll('.cl-order-move'))if(move.parentNode!==actions)actions.prepend(move);
   for(const b of actions.querySelectorAll('button')){
    const label=b.textContent.trim();if(label==='Modifier'||label==='Détails'){b.title=label;b.setAttribute('aria-label',label);b.dataset.actionLabel=label;b.textContent=label==='Modifier'?'✎':'⋯';}
   }
   for(const n of row.querySelectorAll('.ce-text,.ce-scene,.ce-technical'))n.title=n.textContent.trim();
  }
 }
 new MutationObserver(compactRows).observe(host,{childList:true,subtree:true});compactRows();root.CLBuilderRefresh?.();
 // Header offsets are derived from actual height, including smaller laptops.
 const measure=()=>{document.documentElement.style.setProperty('--cl-builder-top',header.getBoundingClientRect().height+'px');document.documentElement.style.setProperty('--cl-builder-batch-height',selectionBar.getBoundingClientRect().height+'px');};
 const resize=new ResizeObserver(measure);resize.observe(header);resize.observe(selectionBar);measure();
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})(typeof window==='undefined'?globalThis:window);
