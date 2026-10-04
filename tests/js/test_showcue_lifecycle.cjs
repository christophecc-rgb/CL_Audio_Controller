const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const script=fs.readFileSync('static/showcue-lifecycle.js','utf8');
let release,fail=false,confirms=[],requests=[],nativeResult={status:'saved',path:'/temporary/Bureau/Show.csv'},saved=false;
const message={textContent:''},shell={inert:false},links=[];
const context={window:null,document:{getElementById:()=>message,querySelector:()=>shell,addEventListener(){},body:{append(){}},createElement:()=>{const a={click(){links.push(this)},remove(){}};return a}},
location:{href:'http://127.0.0.1:5050/show-info/builder'},URL,Uint8Array,String,Error,JSON,
setTimeout(){},clearTimeout(){},btoa:value=>Buffer.from(value,'binary').toString('base64'),
confirm:()=>confirms.shift()||false,preview:null,sessionId:'session_a',documentData:{revision:7},builderEditVersion:1,builderSavedVersion:0,builderPendingSaves:0,autosaveTimer:null,builderSaveQueue:Promise.resolve(),
api:async()=>({ok:true}),fetch:async url=>{requests.push(url);return {ok:true,headers:{get:()=>`attachment; filename="Show.csv"`},blob:async()=>new Blob(['cue;name'])}},
clBuilderDraft:{persist(){}},pywebview:{api:{save_export:async()=>nativeResult}}};
context.window=context;
context.save=()=>{context.builderPendingSaves++;context.builderSaveQueue=new Promise((resolve,reject)=>{release=()=>{context.builderPendingSaves--;if(fail)reject(Error('Administration verrouillée'));else{context.builderSavedVersion=context.builderEditVersion;saved=true;resolve()}}});return context.builderSaveQueue};
const ctx=vm.createContext(context);vm.runInContext(script,ctx);
(async()=>{
 const first=context.clBuilderLifecycle.download('/show-info/builder/export.csv');
 assert.equal(shell.inert,true);assert.equal(requests.length,0);
 release();await first;
 assert.equal(saved,true);assert.equal(requests.length,1);
 assert.match(requests[0],/session_id=session_a&revision=7/);
 assert.equal(message.textContent,'Fichier enregistré : /temporary/Bureau/Show.csv');
 assert.equal(shell.inert,false);
 context.builderEditVersion++;fail=true;const failed=context.clBuilderLifecycle.download('/show-info/builder/export.csv');release();await failed;
 assert.equal(requests.length,1);assert.match(message.textContent,/Export bloqué : Administration verrouillée/);
 confirms=[false];const stay=context.clBuilderLifecycle.prepareNavigation();release();assert.equal(await stay,false);
 confirms=[true];const discard=context.clBuilderLifecycle.prepareNavigation();release();assert.equal(await discard,true);
 context.preview={cues:[]};confirms=[false];assert.equal(await context.clBuilderLifecycle.prepareNavigation(),false);
 confirms=[true];assert.equal(await context.clBuilderLifecycle.prepareNavigation(),true);
 const noPreviewExport=context.clBuilderLifecycle.download('/show-info/builder/export.csv');await noPreviewExport;assert.equal(requests.length,1);
 context.preview=null;fail=false;nativeResult={status:'cancelled'};
 const cancelled=context.clBuilderLifecycle.download('/show-info/builder/sessions/export');release();await cancelled;assert.equal(message.textContent,'Enregistrement annulé.');
 delete context.pywebview;
 const browser=context.clBuilderLifecycle.download('/show-info/builder/export.csv');release();await browser;
 assert.equal(links.length,1);assert.equal(links[0].download,'Show.csv');assert.match(message.textContent,/Téléchargement demandé/);assert.doesNotMatch(message.textContent,/Fichier enregistré|Bureau/);
 context.builderEditVersion++;confirms=[false];assert.equal(context.clBuilderLifecycle.canClose(),false);
 console.log('PASS: save barrier, native results, browser download, navigation refusal and preview isolation.');
})().catch(e=>{console.error(e);process.exitCode=1});
