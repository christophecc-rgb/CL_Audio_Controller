// Combine the real save pipeline, queue and export barrier; simulate only HTTP/storage.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync('templates/showcue_builder.html','utf8');
const base=source.slice(source.indexOf('async function save(){'),source.indexOf("$('save').onclick",source.indexOf('async function save(){')));
const queue=source.slice(source.indexOf('const saveState=document.createElement'),source.indexOf("};['cues','distribution']",source.indexOf('const saveState=document.createElement')))+'};';
let table={cues:[{text:'Initial'}],distribution:[]},server={revision:3,...table},waiting=[],writes=[],exportRequests=[],downloads=[],failure=null;
const nodes={},listeners={};const $=id=>nodes[id]||(nodes[id]={classList:{add(){}},after(){},textContent:''});
const ctxObject={window:null,documentData:server,preview:null,sessionId:'session_fixture',location:{href:'http://fixture/show-info/builder',reload(){throw Error('Unexpected reload')}},
 $,document:{createElement:()=>({}),getElementById:$,querySelector:()=>({}),addEventListener:(type,callback)=>listeners[type]=callback},
 setTimeout:()=>1,clearTimeout(){},URL,Uint8Array,JSON,Error,confirm:()=>false,
 btoa:value=>Buffer.from(value,'binary').toString('base64'),clBuilderDraft:{persist:()=>true},
 readTables:()=>({...JSON.parse(JSON.stringify(table)),revision:ctxObject.documentData.revision}),
 render(){table=JSON.parse(JSON.stringify(ctxObject.documentData))},showValidation(){},
 api:async(url,options)=>{
   const incoming=JSON.parse(options.body);writes.push(incoming);
   return new Promise((resolve,reject)=>waiting.push(()=>{
     if(failure){reject(Error(failure));return}
     assert.equal(incoming.document.revision,server.revision);
     server={...incoming.document,revision:server.revision+1};resolve({document:server,validation:{}});
   }));
 },
 fetch:async url=>{exportRequests.push(url);assert.match(url,new RegExp('revision='+server.revision));return {ok:true,headers:{get:()=> 'attachment; filename="test.csv"'},blob:async()=>new Blob([JSON.stringify(server)])}},
 pywebview:{api:{save_export:async(name,data)=>{downloads.push(JSON.parse(Buffer.from(data,'base64')));return {status:'saved',path:'/temporary/'+name}}}}};
ctxObject.window=ctxObject;const ctx=vm.createContext(ctxObject);
vm.runInContext(base+queue+fs.readFileSync('static/showcue-lifecycle.js','utf8'),ctx);
const ticks=async()=>{for(let i=0;i<12;i++)await Promise.resolve()};
(async()=>{
 table.cues[0].text='Élodie — immédiatement';vm.runInContext('markDirty()',ctx);
 const immediate=ctxObject.clBuilderLifecycle.download('/show-info/builder/export.csv');await ticks();
 assert.equal(exportRequests.length,0);assert.equal(writes[0].document.cues[0].text,'Élodie — immédiatement');
 waiting.shift()();await immediate;assert.equal(downloads[0].cues[0].text,'Élodie — immédiatement');
 // A first write is pending when more edits and an export arrive.
 const inFlight=vm.runInContext('save()',ctx);await ticks();
 table.cues[0].text='Saisie pendant la sauvegarde';vm.runInContext('markDirty()',ctx);
 const during=ctxObject.clBuilderLifecycle.download('/show-info/builder/export.xlsx');await ticks();
 assert.equal(waiting.length,1);assert.equal(exportRequests.length,1);
 waiting.shift()();await inFlight;await ticks();
 assert.equal(waiting.length,1);assert.equal(exportRequests.length,1);assert.equal(writes.at(-1).document.cues[0].text,'Saisie pendant la sauvegarde');
 waiting.shift()();await during;assert.equal(downloads.at(-1).cues[0].text,'Saisie pendant la sauvegarde');
 // Authorization refusal and revision conflict must never fall back to an old export.
 for(const error of ['Déverrouillage administrateur local requis','Document Builder modifié. Rechargement nécessaire.']){
   failure=error;table.cues[0].text='Non sauvegardé';vm.runInContext('markDirty()',ctx);
   const before=exportRequests.length,refused=ctxObject.clBuilderLifecycle.download('/show-info/builder/export.csv');await ticks();
   waiting.shift()();await refused;
   assert.equal(exportRequests.length,before);assert.match($('message').textContent,/Export bloqué/);
 }
 assert.equal(vm.runInContext('autosaveBlocked',ctx),true);
 assert.equal(ctxObject.clBuilderLifecycle.canClose(),false);
 assert.match($('message').textContent,/Rechargement nécessaire/);
 console.log('PASS: real save queue blocks stale exportRequests immediately, in-flight, after admin refusal and on revision conflict.');
})().catch(e=>{console.error(e);process.exitCode=1});
