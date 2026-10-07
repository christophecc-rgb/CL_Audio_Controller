const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync('templates/showcue_builder.html','utf8');
const script=html.match(/<script id="showcue-import-safe-ui">([\s\S]*?)<\/script>/)[1];
class Element{
 constructor(){this.children=[];this.classList={add(){}};this.handlers={};this.textContent='';}
 append(...nodes){this.children.push(...nodes);} prepend(n){this.children.unshift(n);}
 after(n){this.description=n;} addEventListener(k,fn){this.handlers[k]=fn;}
 querySelector(q){return q==='button'?this.button:null;}
}
const labels={};const inputs={};let archiveClicks=0;
for(const id of ['import','import-distribution-only','import-pdf']){
 const label=new Element();label.button=new Element();labels[id]=label;
 inputs[id]={closest:()=>label};
}
inputs['cl-session-upload']={click:()=>archiveClicks++};
const panel=new Element();panel.querySelectorAll=()=>[];
const menu={querySelector:q=>q.includes('summary')?{textContent:'IMPORTER'}:panel};
const document={readyState:'complete',querySelectorAll:()=>[menu],getElementById:id=>inputs[id],createElement:()=>new Element()};
vm.runInNewContext(script,{document,setTimeout(){}});
assert.equal(labels.import.button.textContent,'IMPORTER UN BUILDER CSV / XLSX');
assert.equal(inputs.import.accept,'.csv,.xlsx');
assert.match(labels.import.description.textContent,/Prévisualisation uniquement/);
assert.match(labels['import-distribution-only'].button.textContent,/DISTRIBUTION CSV \/ XLSX/);
assert.equal(labels['import-pdf'].button.textContent,'IMPORTER DEPUIS UN PDF');
const archive=panel.children[0].children.find(n=>n.textContent==='IMPORTER / OUVRIR UN SHOWCUE');
assert.equal(archiveClicks,0);archive.handlers.click();assert.equal(archiveClicks,1);
const handler=html.slice(html.indexOf("$('import').onchange="),html.indexOf(";$('adopt').onclick="));
assert.match(handler,/\/show-info\/builder\/import/);
assert.match(handler,/preview=result.document/);assert.match(handler,/unknown_columns/);
assert(!handler.includes('save('));assert(!handler.includes("method:'PUT'"));
assert(html.includes('/show-info/builder/import-distribution'));
assert(html.includes('/show-info/builder/import.pdf'));
assert(fs.readFileSync('static/showcue-sessions.js','utf8').includes('/show-info/builder/sessions/import'));
for(const ext of ['csv','xlsx'])assert(html.includes('/show-info/builder/export.'+ext));
console.log('Import menu wiring, preview-only handler and separate archive workflow: passed');
