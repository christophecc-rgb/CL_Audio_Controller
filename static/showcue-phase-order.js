/* Use the existing cue array/DOM order; no automatic sort or data migration. */
(function(root){
 const normalize=v=>String(v||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9]/g,'');
 function phase(cue){
  const aliases={PRESHOW:'PRESHOW',PREPARATION:'PRESHOW',PREPA:'PRESHOW',ENTRACTE:'ENTRACTE',SHOW:'SHOW',FIN:'FIN',FINDUSHOW:'FIN'};
  return aliases[normalize(cue.phase)]||aliases[normalize(cue.section)]||'SHOW';
 }
 function organize(cues,sortPhase){
  const phases=['PRESHOW','ENTRACTE','SHOW','FIN'];
  return phases.flatMap(p=>{
   const group=cues.filter(c=>phase(c)===p);
   if(p!==sortPhase)return group;
   // Untimed/invalid cues keep their slots. Sort only timed peers in this phase.
   const timed=group.filter(c=>/^\d{2}:\d{2}:\d{2}:\d{2}$/.test(c.timecode||'')).sort((a,b)=>a.timecode.localeCompare(b.timecode));
   let i=0;return group.map(c=>/^\d{2}:\d{2}:\d{2}:\d{2}$/.test(c.timecode||'')?timed[i++]:c);
  });
 }
 if(typeof module!=='undefined'&&module.exports){module.exports={phase,organize};return;}
 root.CLBuilderOrganization={phase,organize};
 function install(){
  const source=document.getElementById('cues');if(!source)return;
  const controls=document.createElement('div');controls.className='filters';
  const label=document.createElement('strong');label.textContent='TRIER / ORGANISER';controls.append(label);
  function apply(sortPhase){
   const rows=[...source.rows],cues=rows.map(row=>{const cue={row};for(const k of ['phase','section','timecode']){const field=row.querySelector('[data-key="'+k+'"]');cue[k]=field?.value??field?.textContent??'';}return cue;});
   organize(cues,sortPhase).forEach(c=>source.append(c.row));
   source.dispatchEvent(new Event('change',{bubbles:true}));
   document.getElementById('message').textContent='Ordre regroupé : PRESHOW → ENTRACTE → SHOW → FIN. '+(sortPhase?'Tri TC volontaire : '+sortPhase+'. ':'')+'Cues sans TC conservés à leur place dans chaque phase.';
  }
  for(const [text,p] of [['Regrouper par phases',null],['Trier SHOW par TC','SHOW'],['Trier PRESHOW par TC','PRESHOW']]){
   const b=document.createElement('button');b.type='button';b.textContent=text;b.onclick=()=>apply(p);controls.append(b);
  }
  document.getElementById('cue-consultation')?.before(controls);
  // Source order remains the save source, including manual moves of untimed cues.
  function buttons(){
   for(const row of document.querySelectorAll('#cue-consultation .ce-cue')){
    if(row.querySelector('.cl-order-move'))continue;
    const cell=row.lastElementChild;
    for(const [text,delta] of [['↑',-1],['↓',1]]){
     const b=document.createElement('button');b.type='button';b.className='cl-order-move';b.textContent=text;b.title='Déplacer le cue '+(delta<0?'vers le haut':'vers le bas');
     b.onclick=()=>{
      const rows=[...source.rows],current=rows.find(r=>r.dataset.id===row.dataset.cueId),index=rows.indexOf(current),other=rows[index+delta];
      if(!current||!other)return;
      if(delta<0)source.insertBefore(current,other);else source.insertBefore(other,current);
      source.dispatchEvent(new Event('change',{bubbles:true}));
     };cell.append(b);
    }
   }
  }
  const host=document.getElementById('cue-consultation');if(host)new MutationObserver(buttons).observe(host,{childList:true,subtree:true});buttons();
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})(typeof window==='undefined'?globalThis:window);
