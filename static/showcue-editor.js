/* CL Cue Editor consultation. The existing #cues DOM remains the save source.
 * This projection never persists computed equipment, inferred roles or defaults. */
(function(root){
'use strict';
const text = value => String(value ?? '').trim();
const key = value => text(value).toLocaleLowerCase('fr');
const roleKey = value => key(value) === 'preshow punk' ? 'punk' : key(value);
const rolesOf = value => [...new Map(text(value).split('/').map(text).filter(Boolean).map(v => [roleKey(v),v])).values()];
const choices = (slots, type) => [...new Set(slots.filter(s => s.type === type).map(s => text(s.value)).filter(Boolean))];
function summarizeCue(cue, distribution){
    const roles = rolesOf(cue.role), warnings = [], assignments = cue.role_assignments || {};
    const participants = roles.map(role => {
        const active = distribution.filter(d => roleKey(d.role) === roleKey(role) && d.active);
        const dist = active.length === 1 ? active[0] : null;
        const slots = dist?.equipment_slots || [];
        const assignment = assignments[Object.keys(assignments).find(r => roleKey(r) === roleKey(role))] || {};
        const selected = {}, resolution = {}, available = {};
        for(const [field,type] of [['microphone','MICRO'],['iem','IEM'],['equipment','ÉQUIPEMENT']]){
            available[field] = choices(slots,type);
            const global = text(cue[field]);
            if(text(assignment[field])){
                selected[field] = text(assignment[field]); resolution[field] = 'Choix par rôle';
            }else if(roles.length === 1 && global){
                selected[field] = global; resolution[field] = 'Surcharge du cue';
            }else if(available[field].length === 1){
                selected[field] = available[field][0]; resolution[field] = 'Affectation active · choix unique';
            }else{
                selected[field] = ''; resolution[field] = available[field].length > 1 ? 'Choix non renseigné' : 'Non renseigné';
            }
            if(selected[field] && available[field].length && !available[field].some(v => key(v) === key(selected[field]))){
                warnings.push(role+' : '+(field==='microphone'?'micro':field==='iem'?'IEM':'équipement')+' hors affectation');
            }
        }
        if(!dist) warnings.push(role+' : '+(active.length > 1 ? 'plusieurs artistes actifs' : 'aucun artiste actif'));
        return {role, artist: roles.length === 1 && text(cue.artist) ? text(cue.artist) : text(dist?.artist),
            artistOrigin: roles.length === 1 && text(cue.artist) ? 'Surcharge du cue' : 'Casting actif',
            selected, resolution, available, slots, ambiguousMicro: !selected.microphone && available.microphone.length > 1};
    });
    for(const field of ['microphone','iem','equipment']){
        const global = text(cue[field]);
        const perRole = participants.filter(p => p.resolution[field] === 'Choix par rôle');
        if(global && perRole.length && (roles.length > 1 || perRole.some(p => key(p.selected[field]) !== key(global)))){
            warnings.push('Ancien '+(field==='microphone'?'micro':field==='iem'?'IEM':'équipement')+' global '+
                (perRole.some(p=>key(p.selected[field]) === key(global)) && roles.length > 1 ? 'à vérifier' : 'contradictoire'));
        }else if(global && roles.length > 1){
            warnings.push('Choix global '+(field==='microphone'?'micro':field==='iem'?'IEM':'équipement')+' non attribué à un rôle');
        }
    }
    // Notes beyond a bare PDF page can include operational instructions: never hide their existence.
    const notes = text(cue.notes);
    const noteSignal = /[àa]\s+(v[ée]rifier|confirmer)/i.test(notes) ? 'Note à vérifier' :
        notes && !/^PDF\s+p\.\s*\d+$/i.test(notes) ? 'Consigne / note' : '';
    return {participants, warnings:[...new Set(warnings)], noteSignal};
}
if(typeof module !== 'undefined' && module.exports){ module.exports = {summarizeCue,rolesOf}; return; }
root.ShowCueConsultation = {summarizeCue};
const source = document.getElementById('cues');
if(!source) return;
const $ = id => document.getElementById(id);
const el = (tag, cls='', value) => {const n=document.createElement(tag);n.className=cls;if(value!==undefined)n.textContent=value;return n;};
const button = (label, action, cls='') => {const n=el('button',cls,label);n.type='button';n.onclick=action;return n;};
const read = (row,k) => {const n=row.querySelector('[data-key="'+k+'"]');return text(n?.value ?? n?.textContent);};
const cueFromRow = row => {
    const cue={id:row.dataset.id};
    for(const k of [...cueKeys,'origin','notes']) cue[k]=read(row,k);
    for(const k of postKeys) cue[k]=Boolean(row.querySelector('[data-key="'+k+'"]')?.checked);
    try{cue.role_assignments=JSON.parse(row.dataset.roleAssignments || '{}');}catch(_){cue.role_assignments={};}
    return cue;
};
const distributionFromDom = () => [...$('distribution').rows].map(row=>({
    role:read(row,'role'),artist:read(row,'artist'),active:!!row.querySelector('[data-key="active"]')?.checked,
    equipment_slots:[...row.querySelectorAll('.equipment-slot')].map(n=>({type:n.querySelector('[data-slot-key="type"]').value,value:n.querySelector('[data-slot-key="value"]').value}))
}));
const sourceWrap=source.closest('.table-wrap');
const host=el('section','ce-consultation');host.id='cue-consultation';
sourceWrap.before(host);
sourceWrap.hidden=true;sourceWrap.classList.add('ce-source');
document.body.classList.add('ce-enabled');
const tools=el('div','ce-view-tools');
let selectionMode=false;
const selectionButton=button('Sélectionner',()=>{selectionMode=!selectionMode;refresh();});
tools.append(el('span','ce-view-label','CONDUITE · VUE DE CONSULTATION'),selectionButton);
const table=el('table','ce-table');table.setAttribute('aria-label','Cues');
const head=el('thead'),hr=el('tr');
for(const label of ['N°','REPÈRE','SOURCE / SCÈNE','TEXTE / ACTION','RÔLE · ARTISTE / MATÉRIEL']) hr.append(el('th','',label));
head.append(hr);const body=el('tbody');table.append(head,body);host.append(tools,table);
const dialog=el('dialog','ce-dialog');dialog.id='cue-panel';dialog.setAttribute('aria-labelledby','cue-panel-title');
const form=el('form'),panelHeader=el('header','ce-panel-header'),title=el('h2');title.id='cue-panel-title';
const closeButton=button('Fermer',()=>dialog.close());panelHeader.append(title,closeButton);
const content=el('div','ce-panel-content'),footer=el('footer','ce-panel-footer'),error=el('div','ce-panel-error');error.setAttribute('role','alert');
form.append(panelHeader,content,error,footer);dialog.append(form);document.body.append(dialog);
let opened=null, savedFocus=null;
const group=(label,parent=content)=>{const section=el('section','ce-detail-group');section.append(el('h3','',label));parent.append(section);return section;};
const fact=(parent,label,value)=>{const n=el('div','ce-fact');n.append(el('span','ce-fact-label',label),el('div','',text(value)||'—'));parent.append(n);};
const sourceRow=id=>[...source.rows].find(r=>r.dataset.id===id);
function openPanel(id,mode,newCue=null){
    const row=sourceRow(id);if(!row&&!newCue)return;
    savedFocus=document.activeElement;opened={id,mode,isNew:!!newCue,baseline:newCue||cueFromRow(row),revision:documentData.revision};
    content.replaceChildren();footer.replaceChildren();error.textContent='';
    title.textContent=(mode==='edit'?'Modifier':'Détails')+' · cue '+opened.baseline.number;
    if(mode==='edit') buildForm(opened.baseline);else buildDetails(opened.baseline);
    if(!dialog.open)dialog.showModal();content.scrollTop=0;
}
dialog.addEventListener('close',()=>{opened=null;savedFocus?.focus();});
function buildDetails(cue){
    const summary=summarizeCue(cue,distributionFromDom());
    const c=group('Classification');fact(c,'Type',cue.type);fact(c,'Famille',root.showcueCueKind(cue).label);fact(c,'Section',cue.section);
    const a=group('Affectation');
    if(!summary.participants.length)fact(a,'Rôle','Aucun rôle attribué');
    for(const p of summary.participants){
        const box=el('div','ce-participant-detail');a.append(box);box.append(el('h4','',p.role+' · '+(p.artist||'AUCUN ACTIF')));
        fact(box,'Artiste · résolution',p.artistOrigin);
        fact(box,'Matériel disponible',p.slots.filter(s=>text(s.value)).map(s=>s.type+' : '+s.value).join('\n'));
        for(const [field,label] of [['microphone','Micro choisi'],['iem','IEM choisi'],['equipment','Équipement choisi']]){
            fact(box,label,p.selected[field] || (p.available[field].length>1?'À CHOISIR':'Non renseigné'));
            fact(box,'Origine du choix',p.resolution[field]);
        }
    }
    fact(a,'Surcharges globales', ['artist','microphone','iem','equipment'].map(k=>k+' : '+(cue[k]||'—')).join('\n'));
    fact(a,'Choix par rôle · role_assignments',JSON.stringify(cue.role_assignments,null,2));
    for(const w of summary.warnings)a.append(el('p','ce-warning',w));
    const p=group('Provenance');fact(p,'Source / scène',cue.source);fact(p,'Origine',cue.origin);fact(p,'Notes / références d’import',cue.notes);
    fact(p,'Identifiant Builder',cue.id);fact(p,'Révision Builder',documentData.revision);
    fact(p,'Destinations',postKeys.filter(k=>cue[k]).map(k=>k.toUpperCase()).join(' · ')||'Aucune');
    footer.append(button('Modifier',()=>openPanel(cue.id,'edit'),'primary'),button('Fermer',()=>dialog.close()));
}
const fieldLabels={number:'Numéro',timecode:'Repère / timecode',source:'Source / scène',text:'Texte / action',type:'Type',section:'Section',role:'Rôle(s)',artist:'Artiste forcé',microphone:'Micro global',iem:'IEM global',equipment:'Équipement global',origin:'Origine',notes:'Notes / références d’import'};
let fields={},draftAssignments={};
function inputField(parent,k,value,multiline=false){
    const label=el('label','ce-form-field');label.append(el('span','',fieldLabels[k]||k));
    const input=el(multiline?'textarea':'input');if(!multiline)input.type='text';input.value=value||'';input.dataset.editKey=k;
    label.append(input);parent.append(label);fields[k]=input;return input;
}
function buildForm(cue){
    fields={};draftAssignments=JSON.parse(JSON.stringify(cue.role_assignments||{}));
    const main=group('Cue');main.classList.add('ce-form-grid');
    for(const k of ['number','timecode','source','text'])inputField(main,k,cue[k],k==='text');
    const capture=button('Capturer le TC',async()=>{
        capture.disabled=true;error.textContent='';
        try{const result=await api('/show-info/capture',{method:'POST',body:'{}'});if(!result.timecode)throw new Error('Aucun LTC capturable.');fields.timecode.value=result.timecode;}
        catch(e){error.textContent=e.message;}finally{capture.disabled=false;}
    });fields.timecode.parentElement.append(capture);
    const assignment=group('Rôles et matériel du cue');

    /*
     * CL_SHOWCUE_EDITOR_MULTIROLE_CONTROLS_V1
     *
     * Le stockage métier reste inchangé :
     *   cue.role = "MARCEL / DIRECTRICE"
     *   cue.role_assignments = {...}
     *
     * Cette interface évite simplement de demander à l'utilisateur
     * de saisir manuellement les séparateurs "/".
     */
    const roleInput=el('input');
    roleInput.type='hidden';
    roleInput.value=cue.role||'';
    roleInput.dataset.editKey='role';
    fields.role=roleInput;
    assignment.append(roleInput);

    let draftRoles=rolesOf(cue.role);
    const knownRoles=[...new Map(
        distributionFromDom()
            .map(d=>text(d.role))
            .filter(Boolean)
            .map(role=>[roleKey(role),role])
    ).values()];

    const roleControls=el('div','ce-role-controls');
    const roleFields=el('div','ce-role-fields');
    assignment.append(
        roleControls,
        el('p','ce-help','Ajoutez ou retirez les rôles concernés par ce cue. Les choix Micro / IEM / Équipement restent propres à chaque rôle.'),
        roleFields
    );

    const syncRoleValue=()=>{
        roleInput.value=draftRoles.join(' / ');
    };

    const assignmentKeyFor=role=>
        Object.keys(draftAssignments).find(k=>roleKey(k)===roleKey(role));

    const migrateAssignment=(oldRole,newRole)=>{
        const oldKey=assignmentKeyFor(oldRole);
        if(!oldKey || roleKey(oldRole)===roleKey(newRole))return;

        const newKey=assignmentKeyFor(newRole);
        const previous={...(draftAssignments[oldKey]||{})};

        if(newKey){
            draftAssignments[newKey]={
                ...previous,
                ...(draftAssignments[newKey]||{})
            };
        }else{
            draftAssignments[newRole]=previous;
        }

        delete draftAssignments[oldKey];
    };

    const removeAssignmentFor=role=>{
        const storedKey=assignmentKeyFor(role);
        if(storedKey)delete draftAssignments[storedKey];
    };

    const paintRoleFields=()=>{
        roleFields.replaceChildren();

        const current={
            ...cue,
            role:roleInput.value,
            role_assignments:draftAssignments
        };

        for(const p of summarizeCue(current,distributionFromDom()).participants){
            const box=el('div','ce-participant-detail');
            box.append(el('h4','',p.role+' · '+(p.artist||'AUCUN ACTIF')));

            for(const [field,label] of [
                ['microphone','Micro choisi'],
                ['iem','IEM choisi'],
                ['equipment','Équipement choisi']
            ]){
                const l=el('label','ce-form-field');
                l.append(el('span','',label));

                const select=el('select');
                select.dataset.assignmentRole=p.role;
                select.dataset.assignmentField=field;

                const storedKey=assignmentKeyFor(p.role)||p.role;
                const selectedValue=text(draftAssignments[storedKey]?.[field]);
                const options=[...p.available[field]];

                if(selectedValue&&!options.includes(selectedValue)){
                    options.push(selectedValue);
                }

                select.add(new Option(
                    p.resolution[field]==='Surcharge du cue'
                        ? 'Hériter du choix global · '+p.selected[field]
                        : p.available[field].length===1
                            ? 'AUTO · '+p.available[field][0]
                            : p.available[field].length>1
                                ? '— À CHOISIR —'
                                : '— NON RENSEIGNÉ —',
                    ''
                ));

                for(const value of options){
                    select.add(new Option(value,value));
                }

                select.value=selectedValue;

                select.onchange=()=>{
                    const keyNow=assignmentKeyFor(p.role)||p.role;
                    const data={...(draftAssignments[keyNow]||{})};

                    if(select.value)data[field]=select.value;
                    else delete data[field];

                    if(Object.keys(data).length){
                        draftAssignments[keyNow]=data;
                    }else{
                        delete draftAssignments[keyNow];
                    }
                };

                l.append(select);
                box.append(l);
            }

            roleFields.append(box);
        }
    };

    const paintRoleControls=()=>{
        roleControls.replaceChildren();

        draftRoles.forEach((role,index)=>{
            const row=el('div','ce-role-control-row');
            const select=el('select','ce-role-select');

            select.add(new Option('— RÔLE —',''));

            for(const knownRole of knownRoles){
                select.add(new Option(knownRole,knownRole));
            }

            if(role && !knownRoles.some(r=>roleKey(r)===roleKey(role))){
                select.add(new Option(role,role));
            }

            select.value=role;

            select.onchange=()=>{
                const next=text(select.value);

                if(!next){
                    error.textContent='Choisissez un rôle.';
                    select.value=draftRoles[index];
                    return;
                }

                if(
                    draftRoles.some(
                        (existing,i)=>i!==index && roleKey(existing)===roleKey(next)
                    )
                ){
                    error.textContent='Ce rôle est déjà présent sur le cue.';
                    select.value=draftRoles[index];
                    return;
                }

                error.textContent='';

                const previous=draftRoles[index];
                migrateAssignment(previous,next);
                draftRoles[index]=next;

                syncRoleValue();
                paintRoleControls();
                paintRoleFields();
            };

            const removeRole=button('Retirer',()=>{
                const removed=draftRoles[index];
                draftRoles.splice(index,1);
                removeAssignmentFor(removed);

                syncRoleValue();
                paintRoleControls();
                paintRoleFields();
            },'danger');

            row.append(select,removeRole);
            roleControls.append(row);
        });

        const addRow=el('div','ce-role-add-row');
        const addSelect=el('select','ce-role-add-select');
        addSelect.add(new Option('— Ajouter un rôle —',''));

        for(const role of knownRoles){
            if(!draftRoles.some(existing=>roleKey(existing)===roleKey(role))){
                addSelect.add(new Option(role,role));
            }
        }

        const addRole=button('+ Ajouter un rôle',()=>{
            const role=text(addSelect.value);

            if(!role){
                error.textContent='Choisissez le rôle à ajouter.';
                return;
            }

            if(draftRoles.some(existing=>roleKey(existing)===roleKey(role))){
                error.textContent='Ce rôle est déjà présent sur le cue.';
                return;
            }

            error.textContent='';
            draftRoles.push(role);

            syncRoleValue();
            paintRoleControls();
            paintRoleFields();
        },'action-blue');

        addRow.append(addSelect,addRole);
        roleControls.append(addRow);
    };

    syncRoleValue();
    paintRoleControls();
    paintRoleFields();
    const classif=group('Classification');classif.classList.add('ce-form-grid');
    inputField(classif,'type',cue.type);const section=inputField(classif,'section',cue.section);
    const sections=el('datalist');sections.id='ce-section-options';for(const value of builderSectionValues()){const o=el('option');o.value=value;sections.append(o);}section.setAttribute('list',sections.id);classif.append(sections);
    const destinations=group('Destinations');destinations.classList.add('ce-destinations');
    for(const k of postKeys){const l=el('label'),n=el('input');n.type='checkbox';n.checked=cue[k];n.dataset.editKey=k;fields[k]=n;l.append(n,document.createTextNode(k.toUpperCase()));destinations.append(l);}
    const advanced=el('details','ce-edit-advanced');advanced.append(el('summary','','Surcharges globales et provenance'));content.append(advanced);
    const advancedFields=group('Surcharges conservées',advanced);advancedFields.classList.add('ce-form-grid');
    advancedFields.append(el('p','ce-help','Les choix par rôle sont prioritaires. Une ancienne surcharge globale est conservée tant que vous ne la modifiez pas.'));
    for(const k of ['artist','microphone','iem','equipment','origin','notes'])inputField(advancedFields,k,cue[k],k==='notes');
    const remove=button('Supprimer le cue',async()=>{
        if(!confirm('Supprimer ce cue du Builder ?'))return;
        const row=sourceRow(cue.id);if(!row){dialog.close();return;}
        row.querySelector('.row-actions button').click();dialog.close();refresh();
    },'danger');
    const submit=el('button','primary','Enregistrer');submit.type='submit';footer.append(remove,button('Annuler',()=>dialog.close()),submit);
}
form.addEventListener('submit',async event=>{
    event.preventDefault();if(opened?.mode!=='edit')return;
    let row=sourceRow(opened.id);if(!row&&!opened.isNew){error.textContent='Ce cue n’existe plus. Fermez puis rechargez.';return;}
    // Do not overwrite an intervening import, bulk edit or save while this draft was open.
    if(row && JSON.stringify(cueFromRow(row))!==JSON.stringify(opened.baseline)){
        error.textContent='Ce cue a changé pendant l’édition. Fermez puis ouvrez à nouveau Modifier.';return;
    }
    const next={...opened.baseline};for(const [k,input] of Object.entries(fields)) next[k]=postKeys.includes(k)?input.checked:input.value.trim();
    if(!next.text){error.textContent='Le texte du cue est requis.';return;}
    if(next.timecode&&!/^\d{2}:\d{2}:\d{2}:\d{2}$/.test(next.timecode)){error.textContent='Timecode attendu : HH:MM:SS:FF.';return;}
    if(!postKeys.some(k=>next[k])){error.textContent='Sélectionnez au moins un destinataire.';return;}
    if(!row){
        row=cueRow({...next,role_assignments:draftAssignments},source.rows.length);source.append(row);opened.isNew=false;
    }
    for(const k of [...cueKeys,'origin','notes',...postKeys]){
        const n=row.querySelector('[data-key="'+k+'"]');
        if(postKeys.includes(k))n.checked=next[k];
        else if(n.tagName==='SELECT'){
            if(![...n.options].some(o=>o.value===next[k]))n.add(new Option(next[k],next[k]));n.value=next[k];
        }else if('value' in n)n.value=next[k];else n.textContent=next[k];
    }
    row.dataset.roleAssignments=JSON.stringify(draftAssignments);
    opened.baseline=cueFromRow(row); // Retrying a failed save keeps the exact pending values.
    const submit=footer.querySelector('[type="submit"]');submit.disabled=true;error.textContent='';
    try{
        if(preview){readTables();render();}else await save();
        dialog.close();refresh();
    }catch(e){error.textContent=e.message;}finally{submit.disabled=false;}
});
function refresh(){
    const distribution=distributionFromDom();body.replaceChildren();let lastSection=null;
    const rows=[...source.rows];const count=rows.filter(r=>r.querySelector('.builder-bulk-cue-check')?.checked).length;
    const bar=$('builder-bulk-role-bar');if(bar)bar.classList.toggle('ce-bulk-hidden',count===0);
    selectionButton.textContent=selectionMode?'Terminer la sélection':'Sélectionner';
    host.classList.toggle('ce-selecting',selectionMode||count>0);
    for(const sourceRow of rows){
        if(sourceRow.hidden)continue;
        const cue=cueFromRow(sourceRow),summary=summarizeCue(cue,distribution);
        if(cue.section!==lastSection){const r=el('tr','ce-section'),td=el('th','',cue.section||'SANS SECTION');td.colSpan=5;td.scope='rowgroup';r.append(td);body.append(r);lastSection=cue.section;}
        const r=el('tr','ce-cue');r.dataset.cueId=cue.id;
        const num=el('td','ce-number');const select=el('input','ce-select');select.type='checkbox';select.checked=!!sourceRow.querySelector('.builder-bulk-cue-check')?.checked;select.setAttribute('aria-label','Sélectionner le cue '+cue.number);
        select.onchange=()=>{const original=sourceRow.querySelector('.builder-bulk-cue-check');original.checked=select.checked;original.dispatchEvent(new Event('change',{bubbles:true}));refresh();};
        num.append(select,el('span','',cue.number));
        const time=el('td','ce-time',cue.timecode||'SANS TC'),scene=el('td','ce-scene',cue.source||'—'),action=el('td','ce-action');action.append(el('div','ce-text',cue.text||'Cue à compléter'));
        const posts=postKeys.filter(k=>cue[k]);action.append(el('span','ce-posts',posts.length===4?'TOUS':posts.map(k=>k.toUpperCase()).join(' · ')||'AUCUN POSTE'));
        const technical=el('td','ce-technical');
        if(!summary.participants.length){
            technical.append(el('div','ce-no-role','Aucun rôle attribué'));
            const explicit=[cue.microphone,cue.iem&&'IEM : '+cue.iem,cue.equipment].filter(Boolean);if(explicit.length)technical.append(el('div','ce-equipment',explicit.join(' · ')));
            if(cue.artist)technical.append(el('div','ce-help','Artiste forcé : '+cue.artist));
        }
        for(const p of summary.participants){
            const block=el('div','ce-person');block.append(el('div','ce-person-name',p.role+' · '+(p.artist||'AUCUN ACTIF')));
            const material=el('div','ce-equipment');
            material.append(el('strong',p.ambiguousMicro?'ce-warning':'',p.selected.microphone || (p.ambiguousMicro?'MICRO À CHOISIR':'Micro non renseigné')));
            if(p.selected.iem)material.append(document.createTextNode(' · IEM : '+p.selected.iem));
            if(p.selected.equipment)material.append(document.createTextNode(' · '+p.selected.equipment));
            block.append(material);technical.append(block);
        }
        for(const warning of summary.warnings)technical.append(el('div','ce-warning','⚠ '+warning));
        if(summary.noteSignal)action.append(el('div','ce-note','• '+summary.noteSignal));
        const actions=el('div','ce-row-actions');actions.append(button('Modifier',()=>openPanel(cue.id,'edit')),button('Détails',()=>openPanel(cue.id,'details')));technical.append(actions);
        r.append(num,time,scene,action,technical);body.append(r);
    }
    if(!body.children.length){const r=el('tr'),td=el('td','','Aucun cue pour ces filtres.');td.colSpan=5;r.append(td);body.append(r);}
}
let scheduled=false;
function schedule(){if(scheduled)return;scheduled=true;requestAnimationFrame(()=>{scheduled=false;refresh();});}
// Observe source changes only; the consultation projection never feeds back into #cues.
new MutationObserver(schedule).observe(source,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['hidden','data-role-assignments']});
new MutationObserver(schedule).observe($('distribution'),{childList:true,subtree:true,characterData:true});
for(const id of ['cues','distribution','builder-bulk-role-bar']){
    const n=$(id);if(n)for(const event of ['input','change','click'])n.addEventListener(event,schedule);
}
// A new cue remains a form draft until explicit validation; Cancel leaves #cues untouched.
$('add-cue').addEventListener('click',event=>{
    event.preventDefault();event.stopImmediatePropagation();
    const cue={id:newBuilderId(),role_assignments:{}};
    for(const k of [...cueKeys,'origin','notes'])cue[k]='';
    for(const k of postKeys)cue[k]=true;
    Object.assign(cue,{number:String(source.rows.length+1),type:'AUTRE',section:$('filter-section').value||'SHOW',origin:'BUILDER'});
    openPanel(cue.id,'edit',cue);
},true);
const pageHeader=document.querySelector('header.top');
if(pageHeader)new ResizeObserver(()=>{
    host.style.setProperty('--ce-top',Math.ceil(pageHeader.getBoundingClientRect().height)+'px');
}).observe(pageHeader);
root.ShowCueConsultation.refresh=refresh;
refresh();
})(typeof window==='undefined'?globalThis:window);
