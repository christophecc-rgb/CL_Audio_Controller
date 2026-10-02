const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert/strict');
const root=path.resolve(__dirname,'../..');
const source=fs.readFileSync(path.join(root,'static/midi-return-visual.js'),'utf8');
const ctx={globalThis:{}};vm.runInNewContext(source,ctx);
const {deviceViewModel,createController}=ctx.globalThis.CLMidiReturnVisual;
const device={id:'console_a',production_supported:true,library:'cl5',expected_midi_program:12,
 returned_midi_program:12,expected_scene_memory:13,returned_scene_memory:13,
 expected_title:'Falling',returned_title:'FALLING',expected_activated_at:100,returned_at:101};
for(const title of ['FALLING',"FALLIN'"]){
 const go=deviceViewModel({...device,returned_title:title,validation_status:'confirmed',visual_state:'confirmed'});
 const direct=deviceViewModel({...device,returned_title:title,validation_status:'stale',visual_state:'mismatch'});
 assert.equal(go.programMatch,true);assert.equal(go.visualState,'confirmed');
 assert.equal(direct.programMatch,true);assert.equal(direct.visualState,'loaded');
 const mismatch=deviceViewModel({...device,returned_midi_program:24,validation_status:'stale',visual_state:'loaded'});
 assert.equal(mismatch.programMatch,false);assert.equal(mismatch.visualState,'mismatch');
}
assert.equal(deviceViewModel({...device,production_supported:false}).visualState,'idle');
assert.equal(deviceViewModel({...device,expected_midi_program:null,visual_state:'mismatch'}).visualState,'waiting');
const phases=[];
const c=createController({applyState:s=>phases.push(s),now:()=>100000,
 requestFrame:()=>{},setTimer:()=>1,clearTimer:()=>{}});
const update=backendState=>c.update({expectedKey:'pc12',hasExpected:true,backendState,finalKey:'return'});
assert.equal(update('mismatch'),'mismatch');
assert.equal(update('waiting'),'waiting'); // Previously retained the old mismatch.
assert.equal(update('loaded'),'loaded');
assert.equal(update('mismatch'),'mismatch'); // A subsequent genuine mismatch remains visible.

const remote=fs.readFileSync(path.join(root,'static/remote-v2.js'),'utf8');
const sync=remote.slice(remote.indexOf('  const syncState ='),remote.indexOf('  if (status) new MutationObserver'));
const nodes={status:{textContent:'● Connecté à AbletonOSC',dataset:{},classList:{contains:()=>false}},
 healthLabel:{},healthDetail:{},footerMessage:{},currentCard:null,sharedLtcTimecode:null,
 document:{body:{classList:{toggle(){}}}}};
const context=vm.createContext(nodes);vm.runInContext(sync,context);
for(const name of ['index.html','ab.html','arrangement.html']){
 const template=fs.readFileSync(path.join(root,'templates',name),'utf8');
 const binding=template.match(/statusEl\.dataset\.abletonHost = .*;/)[0];
 context.statusEl=nodes.status;
 context.state={ableton_target:{host:'MacBook-Pro.local'},draft:{host:'wrong.local'},ip:'192.168.1.138'};
 vm.runInContext(binding+'syncState()',context);
 assert.equal(nodes.healthLabel.textContent,'Connecté à MacBook-Pro.local',name);
 context.state={};vm.runInContext(binding+'syncState()',context);
 assert.equal(nodes.healthLabel.textContent,'Ableton connecté');
}
nodes.status.dataset.abletonHost='MacBook-Pro.local';nodes.status.classList.contains=()=>true;
vm.runInContext('syncState()',context);assert.equal(nodes.healthLabel.textContent,'Hors ligne');
console.log('PASS: GO/direct-Live PC equality, genuine mismatch, stale animation reset, applied hostname on Session/AB/Arrangement.');
