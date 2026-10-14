const assert=require('node:assert/strict');
const {createLightController}=require('../../static/light.js');
function harness(){
 const nodes={};const events={};const calls=[];let responses=[];
 function node(id){return nodes[id]??=( {textContent:'',dataset:{},disabled:false,setAttribute(){},addEventListener(k,f){this[k]=f;}} );}
 const buttons=['go','prev','next','stop'].map(k=>{const n=node(k);n.dataset.action=k;return n;});
 const document={getElementById:node,querySelector:()=>({classList:{toggle(){}}}),querySelectorAll:()=>buttons,addEventListener:(k,f)=>events[k]=f};
 const ui=createLightController({document,fetch:async(url,opt)=>{calls.push({url,opt});const response=responses.shift();return typeof response==='function'?response():response;},setTimeout:()=>1,clearTimeout(){},crypto:{randomUUID:()=> 'unique-id'}});
 return {ui,nodes,events,calls,defer(){let resolve;responses.push(()=>new Promise(r=>{resolve=r;}));return data=>resolve({ok:true,status:200,json:async()=>data});},reply(data,status=200){responses.push({ok:status<400,status,json:async()=>data});},key(key,repeat=false){events.keydown({key,repeat,target:{tagName:'BODY'},preventDefault(){}});},release(key){events.keyup({key});}};
}
const state=(extras={})=>({set_generation:4,set_available:true,ableton_available:true,current_scene:null,current_scene_name:'',prepared_scene:1,prepared_scene_name:'  Scène préparée  ',prepared_duration_seconds:90,next_scene:1,is_playing:false,allowed_actions:['go','prev','next','goto','stop'],state:'ready',...extras});
(async()=>{
 const h=harness();assert.equal(h.nodes.go.disabled,true);
 h.reply(state());await h.ui.poll();assert.equal(h.nodes.state.textContent,'PRÊT');assert.equal(h.nodes['prepared-name'].textContent,'Scène préparée');assert.equal(h.nodes['prepared-duration'].textContent,'01:30');
 h.reply({ok:true,state:state({prepared_scene:2})});await h.ui.action('next');assert.equal(JSON.parse(h.calls.at(-1).opt.body).action,'next');assert.equal(h.nodes['current-name'].textContent,'Aucune scène en cours');
 h.reply({ok:true,state:state()});await h.ui.action('prev');
 h.reply({ok:true,state:state()});await h.ui.action('go');let p=JSON.parse(h.calls.at(-1).opt.body);assert.equal(p.request_id,'unique-id');assert.equal(p.set_generation,4);assert.equal(p.scene,2);assert.equal(h.nodes.state.textContent,'PRÊT');
 h.reply(state({current_scene:1,current_scene_name:'Jouée',is_playing:true}));await h.ui.poll();assert.equal(h.nodes.state.textContent,'LECTURE');
 h.reply({ok:true,state:state()});await h.ui.action('stop');assert.equal(h.nodes.state.textContent,'ARRÊTÉ');
 h.reply({ok:false,message:'Génération obsolète',state:state({set_generation:5})},409);h.reply(state({set_generation:5}));await h.ui.action('go');assert.match(h.nodes.message.textContent,/409.*Génération obsolète/);assert.equal(h.ui.getState().set_generation,5);
 h.reply(state({set_generation:4,prepared_scene_name:'ANCIEN'}));await h.ui.poll();assert.notEqual(h.nodes['prepared-name'].textContent,'ANCIEN');
 h.reply(state({set_generation:5,set_available:false,ableton_available:false,allowed_actions:[],prepared_scene:null}));await h.ui.poll();assert.equal(h.nodes.go.disabled,true);assert.equal(h.nodes.state.textContent,'ABLETON INDISPONIBLE');
 for(const [key,action] of [['Enter','go'],['ArrowLeft','prev'],['ArrowRight','next'],['Escape','stop']]){
  const k=harness();k.reply(state());await k.ui.poll();k.reply({ok:true,state:state()});k.key(key);k.key(key,true);k.key(key);await new Promise(r=>setImmediate(r));assert.equal(k.calls.filter(c=>c.url==='/action').length,1);assert.equal(JSON.parse(k.calls.at(-1).opt.body).action,action);k.release(key);
 }
 // A pending command disables every button and displays no optimistic launch.
 const delayed=harness();delayed.reply(state());await delayed.ui.poll();const finish=delayed.defer();const transaction=delayed.ui.action('go');assert.equal(delayed.nodes.go.disabled,true);assert.equal(delayed.nodes.stop.disabled,true);assert.equal(delayed.nodes['current-name'].textContent,'Aucune scène en cours');await delayed.ui.action('go');assert.equal(delayed.calls.length,2);finish({ok:true,state:state()});await transaction;assert.equal(delayed.nodes.go.disabled,false);
 // An older in-flight status cannot overwrite the newer action response.
 const raced=harness();raced.reply(state());await raced.ui.poll();const old=raced.defer();const polling=raced.ui.poll();raced.reply({ok:true,state:state({prepared_scene:2,prepared_scene_name:'Nouvelle'})});await raced.ui.action('next');old(state({prepared_scene_name:'Périmée'}));await polling;assert.equal(raced.nodes['prepared-name'].textContent,'Nouvelle');
 const failure=harness();failure.reply({message:'Erreur précise'},500);await failure.ui.poll();assert.equal(failure.nodes.go.disabled,true);assert.match(failure.nodes.message.textContent,/500.*Erreur précise/);
 const timing=harness();timing.reply(state({is_playing:true,current_scene:1,current_duration_seconds:198,current_position_seconds:102,current_remaining_seconds:96}));await timing.ui.poll();assert.equal(timing.nodes['current-position'].textContent,'01:42');assert.equal(timing.nodes['current-duration'].textContent,'03:18');assert.equal(timing.nodes['current-remaining'].textContent,'01:36');timing.reply(state());await timing.ui.poll();assert.equal(timing.nodes['current-duration'].textContent,'—');
 console.log('Light UI: GO/navigation/STOP, confirmation, unavailable, 409/stale generation, keyboard duplicates OK');
})().catch(e=>{console.error(e);process.exitCode=1;});
