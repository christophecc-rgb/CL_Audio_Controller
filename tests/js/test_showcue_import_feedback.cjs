const fs=require('fs'),vm=require('vm'),assert=require('assert');
(async()=>{
 const nodes={import:{},adopt:{style:{}},'header.top':{append(n){nodes.panel=n}}};let calls=[],states=[];
 const context={document:{readyState:'complete',getElementById:id=>nodes[id],querySelector:q=>nodes[q],createElement:()=>({style:{},children:[],value:'',append(...n){this.children.push(...n)},setAttribute(){},set textContent(v){this.value=v},get textContent(){return this.value+this.children.map(n=>n.textContent||'').join('')}})},api:async(url)=>{calls.push(url);return {document:{cues:[{},{}]},unknown_columns:['Inconnue'],diagnostics:{conduite:{sheet:'Tableau Numbers',header_row:4},encoding:'cp1252',separator:';',warnings:['Windows-1252 présumé : vérifier les accents']}}},window:{},setSaveState:v=>states.push(v)};
 nodes.import.onchange=async()=>context.api('/show-info/builder/import');nodes.adopt.onclick=()=>{};
 vm.createContext(context);vm.runInContext(fs.readFileSync('static/showcue-import-feedback.js','utf8'),context);
 const pending=nodes.import.onchange({target:{files:[{name:'essai.csv'}]}});
 assert.match(nodes.panel.textContent,/FICHIER SÉLECTIONNÉ/);await pending;
 assert.match(nodes.panel.textContent,/PRÉVISUALISATION PRÊTE/);assert.match(nodes.panel.textContent,/2 cues détectés/);assert.match(nodes.panel.textContent,/1 colonnes inconnues : Inconnue/);
 assert.match(nodes.panel.textContent,/Tableau Numbers · En-têtes : ligne 4/);
 assert.match(nodes.panel.textContent,/Encodage : cp1252 · Séparateur : ;/);
 assert.match(nodes.panel.textContent,/Windows-1252 présumé : vérifier les accents/);
 assert.deepEqual(calls,['/show-info/builder/import']);nodes.adopt.onclick({});assert.match(nodes.panel.textContent,/non encore sauvegardées/);assert(nodes.panel.children.includes(nodes.adopt));assert.equal(nodes.panel.children[2].hidden,false);
 context.setSaveState('BUILDER SAUVEGARDÉ');assert.match(nodes.panel.textContent,/Sauvegarde terminée/);
 const before=nodes.panel.textContent;
 for(const route of ['/show-info/builder/import-distribution','/show-info/builder/import.pdf','/show-info/builder/sessions/import'])await context.api(route);
 assert.equal(nodes.panel.textContent,before);
 const html=fs.readFileSync('templates/showcue_builder.html','utf8');const apiSource=html.slice(html.indexOf('async function api('),html.indexOf('\nfunction ',html.indexOf('async function api(')));
 const apiContext={FormData:class{},fetch:async()=>({status:400,ok:false,json:async()=>({ok:false,message:'Colonne Texte absente'})})};vm.createContext(apiContext);vm.runInContext(apiSource,apiContext);
 await assert.rejects(apiContext.api('/show-info/builder/import'),/Erreur 400 — Colonne Texte absente/);
 apiContext.fetch=async()=>({status:502,json:async()=>{throw Error('html')}});
 await assert.rejects(apiContext.api('/show-info/builder/import'),/Erreur 502 — Réponse serveur non JSON/);
 console.log('Import feedback states, counters, adoption/save, HTTP errors and unchanged other workflows: passed');
})().catch(e=>{console.error(e);process.exitCode=1});
// Adoption must not schedule the existing autosave timer for a CSV/XLSX preview.
{
 const html=fs.readFileSync('templates/showcue_builder.html','utf8');
 const fn=html.slice(html.indexOf('function markDirty(event){'),html.indexOf('\nsave=function()',html.indexOf('function markDirty(event){')));
 let scheduled=0;
 const c={preview:null,builderEditVersion:0,autosaveBlocked:false,autosaveTimer:null,window:{clImportExplicitSave:true},setSaveState(){},clearTimeout(){},setTimeout(){scheduled++}};
 vm.createContext(c);vm.runInContext(fn,c);c.markDirty({target:{id:'adopt'}});
 assert.equal(scheduled,0);assert.equal(c.builderEditVersion,1);
}
