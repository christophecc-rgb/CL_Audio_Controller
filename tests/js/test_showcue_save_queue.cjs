const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync('templates/showcue_builder.html','utf8');
const base=source.slice(source.indexOf('async function save(){'),source.indexOf("$('save').onclick",source.indexOf('async function save(){')));
const queue=source.slice(source.indexOf('const saveState=document.createElement'),source.indexOf("};['cues','distribution']",source.indexOf('const saveState=document.createElement')))+ '};';
let table={revision:4,cues:[{text:'before'}]},release,calls=[],renders=0;
const nodes={};const $=id=>nodes[id]||(nodes[id]={classList:{add(){}},after(){}});
const ctx=vm.createContext({$,document:{createElement:()=>({})},setTimeout:()=>1,clearTimeout(){},preview:null,sessionId:'one',documentData:table,
 readTables:()=>JSON.parse(JSON.stringify(table)),render(){renders++},showValidation(){},
 api:async(url,opts)=>{calls.push(JSON.parse(opts.body));return new Promise(resolve=>{release=()=>{const sent=calls.at(-1).document;table.revision=sent.revision+1;resolve({document:{...sent,revision:sent.revision+1},validation:{}})}})}});
vm.runInContext(base+queue,ctx);
(async()=>{
 const first=vm.runInContext('save()',ctx);await Promise.resolve();
 table.cues[0].text='typed during save';vm.runInContext('markDirty()',ctx);
 release();await first;
 assert.equal(renders,0);assert.equal(vm.runInContext('documentData.cues[0].text',ctx),'typed during save');
 assert.equal(vm.runInContext('builderEditVersion>builderSavedVersion',ctx),true);
 const second=vm.runInContext('save()',ctx);await Promise.resolve();release();await second;
 assert.equal(calls[1].document.revision,5);assert.equal(calls[1].document.cues[0].text,'typed during save');
 assert.equal(vm.runInContext('builderEditVersion===builderSavedVersion && builderPendingSaves===0',ctx),true);
 console.log('PASS: queue serializes revisions and retains edits typed during an in-flight save.');
})().catch(e=>{console.error(e);process.exitCode=1});
