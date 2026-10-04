const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync('templates/showcue_builder.html','utf8');
const start=source.indexOf('<script id="showcue-builder-local-draft-v1">')+'<script id="showcue-builder-local-draft-v1">'.length;
const script=source.slice(start,source.indexOf('</script>',start));
function page(serverRevision,draftRevision){
 const key='showcue_builder_draft_v2_one',stored=new Map([[key,JSON.stringify({session_id:'one',document:{revision:draftRevision,cues:[{text:'draft'}],distribution:[]}})]]);
 const listeners={},timers=[],created=[],nodes={};let fail=true;
 const element=()=>({children:[],classList:{remove(){}},append(...items){this.children.push(...items)},after(panel){this.panel=panel},addEventListener(){}});
 const context={window:null,localStorage:{getItem:k=>stored.get(k),setItem:(k,v)=>stored.set(k,v),removeItem:k=>stored.delete(k)},
 document:{getElementById:id=>nodes[id]||(nodes[id]=element()),createElement:()=>{const n=element();created.push(n);return n}},
 sessionId:'one',documentData:{revision:serverRevision,cues:[{text:'server'}],distribution:[]},preview:null,builderEditVersion:1,builderSavedVersion:0,builderPendingSaves:0,
 console,Date,JSON,Number,Array,String,readTables:()=>context.documentData,render(){},setSaveState(){},setTimeout:fn=>timers.push(fn),
 save:async()=>{if(fail)throw Error('Refus');context.builderSavedVersion=context.builderEditVersion},addEventListener:(key,fn)=>listeners[key]=fn};
 context.window=context;const ctx=vm.createContext(context);vm.runInContext(script,ctx);timers.shift()();
 return {ctx,context,stored,key,created,listeners,nodes,setSuccess:()=>{fail=false}};
}
(async()=>{
 for(const revision of [4,7]){
  const p=page(7,revision),original=p.stored.get(p.key);
  assert.equal(p.context.documentData.cues[0].text,'server');
  assert.equal(p.stored.get(p.key),original);
  const panel=p.nodes.message.panel;assert(panel);
  panel.children[0].onclick();assert.match(panel.children.at(-1).textContent,/SERVEUR[\s\S]*BROUILLON/);
  panel.children[1].onclick();assert.equal(p.context.preview.cues[0].text,'draft');
  p.context.clBuilderDraft.persist();assert.equal(p.stored.get(p.key),original); // preview isn't a dirty show
  p.context.preview=null;p.context.documentData={revision:7,cues:[{text:'edited'}],distribution:[]};
  await assert.rejects(()=>vm.runInContext('save()',p.ctx),/Refus/);
  assert(p.stored.has(p.key+'_pending'));
  const event={preventDefault(){this.prevented=true}};p.listeners.beforeunload(event);
  assert.equal(event.prevented,true);assert.equal(p.stored.get(p.key),original);
  p.setSuccess();await vm.runInContext('save()',p.ctx);
  assert.equal(p.stored.has(p.key+'_pending'),false);assert.equal(p.stored.has(p.key),false); // Explicitly recovered and confirmed: now resolved.
 }
 const untouched=page(7,4),original=untouched.stored.get(untouched.key);
 untouched.context.documentData.cues[0].text='Other edits';untouched.setSuccess();
 await vm.runInContext('save()',untouched.ctx);
 assert.equal(untouched.stored.get(untouched.key),original); // A different save cannot erase an unresolved conflicting draft.
 console.log('PASS: conflicting drafts retained, explicit comparison/recovery, previews not persisted, closure guard and rejected saves.');
})().catch(e=>{console.error(e);process.exitCode=1});
