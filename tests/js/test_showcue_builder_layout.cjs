const assert=require('assert'),fs=require('fs');
const {patchCues,moveGroup,selectIds}=require('../../static/showcue-builder-layout.js');
const cues=Array.from({length:12},(_,i)=>({id:'builder_'+i,phase:i%2?'SHOW':'PRESHOW',section:'SECTION '+i,type:'TOP',timecode:'18:00:'+String(i).padStart(2,'0')+':00',text:'Cue '+i,foh:true,ret:false,plt:true,lum:false,role_assignments:{A:{microphone:'HF'}}}));
let selected=selectIds(cues.map(c=>c.id),[],cues[1].id,null,{});
selected=selectIds(cues.map(c=>c.id),selected,cues[8].id,cues[1].id,{shiftKey:true});assert.equal(selected.length,8);
selected=selectIds(cues.map(c=>c.id),selected,cues[10].id,cues[1].id,{metaKey:true});assert.equal(selected.length,9);
selected=selectIds(cues.map(c=>c.id),selected,cues[10].id,cues[1].id,{ctrlKey:true});assert.equal(selected.length,8);
for(const patch of [{phase:'PRESHOW'},{phase:'SHOW'},{section:'ENTRACTE'},{type:'ACTION'},{foh:false,lum:true}]){
 const changed=patchCues(cues,selected,patch);
 for(const [i,c] of changed.entries()){
  assert.equal(c.timecode,cues[i].timecode);assert.equal(c.text,cues[i].text);assert.deepEqual(c.role_assignments,cues[i].role_assignments);
  for(const key of Object.keys(c))assert.deepEqual(c[key],selected.includes(c.id)&&key in patch?patch[key]:cues[i][key]);
 }
}
assert.throws(()=>patchCues(cues,selected,{timecode:'00:00:00:00'}));
for(const position of ['before','after','start','end']){
 const moved=moveGroup(cues,selected,'builder_0',position);assert.deepEqual(moved.filter(c=>selected.includes(c.id)).map(c=>c.id),selected);assert.equal(moved.length,12);
}
assert.deepEqual(moveGroup(cues,selected,'builder_2','before'),cues);
const js=fs.readFileSync('static/showcue-builder-layout.js','utf8');
assert(js.includes('dialog.append(title,sessions)'));assert(js.includes("sessions.open=true"));assert(js.includes("if(!local)return"));assert(js.includes('confirm('));
assert(!js.includes('fetch('));assert(!js.includes("/show-info/builder/import"));
const access=fs.readFileSync('static/showcue-builder-access.js','utf8');assert(access.includes('cl-builder-sessions-dialog'));
console.log('Batch phases/sections/types/destinations, untouched fields, range/modifier selection and stable group moves: passed');

const template=fs.readFileSync('templates/showcue_builder.html','utf8');
assert(!template.includes("orderedBuilderCues(documentData.cues)"), "reload must retain saved manual order");
