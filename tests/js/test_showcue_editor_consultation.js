// NODE_PATH=<playwright packages> node --test tests/js/test_showcue_editor_consultation.js
// Browser requests are all intercepted. No ShowCue service or session is written.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=process.env.SHOWCUE_TEST_ROOT || path.resolve(__dirname,'../..');
const {summarizeCue}=require(path.join(root,'static/showcue-editor.js'));
const distribution=[
 {role:'DIRECTRICE',artist:'Ryan',active:true,equipment_slots:[{type:'MICRO',value:'SHURE BETA 58A HF #3'},{type:'MICRO',value:'DPA 4088 #3'},{type:'IEM',value:'PSM 900 #3'}],notes:''},
 {role:'MARCEL',artist:'Cyril',active:true,equipment_slots:[{type:'MICRO',value:'SHURE BETA 58A HF #2'},{type:'MICRO',value:'DPA 4088 #2'},{type:'IEM',value:'PSM 900 #2'}],notes:''},
 {role:'AVA',artist:'Ava',active:true,equipment_slots:[{type:'MICRO',value:'DPA 4088 #4'},{type:'MICRO',value:'MICRO TABLE #10'}],notes:''},
];
const cue=(number,values)=>({id:'builder_test'+number,number:String(number),timecode:'',source:'SHOWGIRL',text:'TOP DIRECTRICE',type:'TOP MUSIQUE',section:'SHOW',role:'',artist:'',microphone:'',iem:'',equipment:'',foh:true,ret:true,plt:true,lum:true,origin:'IMPORT',notes:'PDF p.2',role_assignments:{},...values});
const fixtures=[
 cue(48,{timecode:'02:03:40:23',role:'DIRECTRICE',microphone:'DPA 4088 #3'}),
 cue(50,{timecode:'03:03:11:19',source:'RÉVÉLATION',text:'TALK DIRECTRICE/MARCEL',type:'AUTRE',role:'MARCEL / DIRECTRICE',microphone:'DPA 4088 #1',role_assignments:{DIRECTRICE:{microphone:'DPA 4088 #3'},MARCEL:{microphone:'SHURE BETA 58A HF #2'}}}),
 cue(52,{timecode:'03:03:24:12',source:'AVA - LE LUSTRE',text:'AVA - LE LUSTRE',type:'AUTRE',role:'AVA'}),
 cue(53,{text:'Repère sans rôle',type:'AUTRE',source:'REPÈRE',section:'ENTRACTE',notes:'À confirmer : attendre le noir',artist:'Override conservé',microphone:'Micro conservé',iem:'IEM conservé',equipment:'Accessoire',lum:false}),
];
const canonical=doc=>{
 const d=structuredClone(doc);delete d.revision;
 d.cues=d.cues.map(c=>{delete c.resolved;if(!c.role_assignments || !Object.keys(c.role_assignments).length)delete c.role_assignments;return c;}).sort((a,b)=>a.id.localeCompare(b.id));
 d.distribution.sort((a,b)=>(a.role+a.artist).localeCompare(b.role+b.artist));return d;
};
test('equipment summary: exact choices, per-role priority, ambiguous mic and absent role',()=>{
 const before=JSON.stringify(fixtures);
 const a=summarizeCue(fixtures[0],distribution).participants[0];assert.equal(a.artist,'Ryan');assert.equal(a.selected.microphone,'DPA 4088 #3');assert.equal(a.selected.iem,'PSM 900 #3');
 const b=summarizeCue(fixtures[1],distribution);assert.equal(b.participants[0].selected.microphone,'SHURE BETA 58A HF #2');assert.equal(b.participants[1].selected.microphone,'DPA 4088 #3');assert.ok(b.warnings.includes('Ancien micro global contradictoire'));
 const c=summarizeCue(fixtures[2],distribution).participants[0];assert.equal(c.selected.microphone,'');assert.equal(c.ambiguousMicro,true);assert.equal(c.available.microphone.length,2);
 assert.equal(summarizeCue(fixtures[3],distribution).participants.length,0);
 assert.equal(JSON.stringify(fixtures),before);
 const single=summarizeCue(cue(1,{role:'CELLO'}),[{role:'CELLO',artist:'Charbel',active:true,equipment_slots:[{type:'MICRO',value:'DPA 4099 #9'}]}]);assert.equal(single.participants[0].selected.microphone,'DPA 4099 #9');
 const noActive=summarizeCue(fixtures[0],distribution.map(d=>({...d,active:false})));assert.equal(noActive.participants[0].artist,'');assert.ok(noActive.warnings.length);
 const overrides=summarizeCue(cue(2,{role:'DIRECTRICE',microphone:'Old',role_assignments:{DIRECTRICE:{microphone:'DPA 4088 #3',iem:'Selected IEM',equipment:'Selected equipment'}}}),distribution);assert.equal(overrides.participants[0].selected.iem,'Selected IEM');assert.equal(overrides.participants[0].selected.equipment,'Selected equipment');assert.ok(overrides.warnings.includes('Ancien micro global contradictoire'));
});
test('full editor: isolated save roundtrip, cancel, details, roles, filtering and responsive layout',async t=>{
 const {chromium}=require('playwright');
 const browser=await chromium.launch({headless:true,executablePath:process.env.SHOWCUE_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  let document=process.env.SHOWCUE_TEST_DOCUMENT ? JSON.parse(fs.readFileSync(process.env.SHOWCUE_TEST_DOCUMENT,'utf8')) : {version:1,revision:251,cues:structuredClone(fixtures),distribution:structuredClone(distribution),equipment_catalog:[]};
  const originalDocument=structuredClone(document);const before=canonical(document);const writes=[];
  const validation=process.env.SHOWCUE_TEST_VALIDATION ? JSON.parse(fs.readFileSync(process.env.SHOWCUE_TEST_VALIDATION,'utf8')) : {total:document.cues.length,timed:3,without_timecode:1,suggestions:0,invalid_timecodes:[],empty_texts:[],possible_duplicates:[],unknown_roles:[],unknown_artists:[],roles_without_active_artist:[],roles_with_multiple_active_artists:[],duplicate_role_artists:[],invalid_equipment_slots:[],duplicate_equipment_slots:[],incomplete_equipment:[],ready:true,destinations:{FOH:4,RET:4,PLT:4,LUM:3}};
  const html=fs.readFileSync(path.join(root,'templates/showcue_builder.html'),'utf8').replace('{{ sections|tojson }}',JSON.stringify(['SHOW','PRESHOW','ENTRACTE']));
  await page.route('**/*',async route=>{
    const req=route.request(),url=new URL(req.url());
    if(url.pathname==='/show-info/builder')return route.fulfill({contentType:'text/html',body:html});
    if(url.pathname==='/show-info/builder/document'){
      if(req.method()==='PUT'){const body=req.postDataJSON();writes.push(structuredClone(body));document={...body.document,revision:document.revision+1};}
      return route.fulfill({json:{ok:true,session_id:'session_test',document,validation}});
    }
    if(url.pathname==='/show-info/builder/resources')return route.fulfill({json:{ok:true,libraries:{},sessions:[]}});
    if(url.pathname==='/assets/paradis%20latin.jpg')return route.fulfill({contentType:'image/jpeg',body:fs.readFileSync(path.join(root,'assets/paradis latin.jpg'))});
    if(url.pathname.startsWith('/static/showcue-editor.'))return route.fulfill({contentType:url.pathname.endsWith('.js')?'application/javascript':'text/css',body:fs.readFileSync(path.join(root,url.pathname.slice(1)),'utf8')});
    if(req.method()!=='GET')throw new Error('Unexpected write: '+url.pathname);
    return route.fulfill({status:204,body:''});
  });
  await page.goto('http://showcue.test/show-info/builder');
  await page.waitForFunction(()=>document.querySelectorAll('.ce-cue').length>0);
  await page.waitForTimeout(1200); // Existing one-shot enhancements settle before the roundtrip assertion.
  assert.equal(writes.length,0,'consultation must not save automatically');
  const row=n=>page.locator('.ce-cue').filter({has:page.locator('.ce-number span',{hasText:new RegExp('^'+n+'$')})});
  assert.match(await row(48).innerText(),/DIRECTRICE · Ryan/);assert.match(await row(48).innerText(),/DPA 4088 #3/);
  assert.match(await row(50).innerText(),/Ancien micro global contradictoire/);assert.doesNotMatch(await row(50).innerText(),/DPA 4088 #1/);
  assert.match(await row(52).innerText(),/MICRO À CHOISIR/);assert.doesNotMatch(await row(52).innerText(),/DPA 4088 #4|MICRO TABLE #10/);
  assert.equal(await page.locator('.ce-table thead th').count(),5);
  assert.equal(await page.locator('#builder-bulk-role-bar').isVisible(),false);
  await row(52).getByRole('button',{name:'Détails',exact:true}).click();
  assert.match(await page.locator('#cue-panel').innerText(),/DPA 4088 #4/);assert.match(await page.locator('#cue-panel').innerText(),/MICRO TABLE #10/);
  await page.locator('#cue-panel').getByRole('button',{name:'Fermer',exact:true}).last().click();
  await row(50).getByRole('button',{name:'Modifier',exact:true}).click();
  await page.locator('[data-edit-key="text"]').fill('Texte annulé');
  await page.locator('#cue-panel').getByRole('button',{name:'Annuler'}).click();
  assert.equal(writes.length,0);assert.deepEqual(canonical(await page.evaluate(()=>readTables())),before);
  await page.getByRole('button',{name:'+ CUE',exact:true}).click();
  await page.locator('#cue-panel').getByRole('button',{name:'Annuler'}).click();
  await page.waitForTimeout(850);
  assert.equal(writes.length,0,'cancel a new cue must not save an empty cue');
  assert.deepEqual(canonical(await page.evaluate(()=>readTables())),before);
  await page.evaluate(()=>save());
  assert.deepEqual(canonical(document),before,'all original values survive save/refresh');
  await row(50).getByRole('button',{name:'Modifier',exact:true}).click();
  const panel=page.locator('#cue-panel');
  await panel.locator('[data-edit-key="text"]').fill('TALK DIRECTRICE/MARCEL — vérifié');
  await panel.getByText('Surcharges globales et provenance',{exact:true}).click();
  const changes={number:'50',timecode:'03:03:11:20',source:'RÉVÉLATION éditée',type:'AUTRE',section:'SHOW',artist:'Artiste forcé conservé',microphone:'DPA 4088 #1',iem:'Global IEM',equipment:'Global equipment',origin:'IMPORT',notes:'PDF p.2 — à confirmer'};
  for(const [k,v] of Object.entries(changes))await panel.locator('[data-edit-key="'+k+'"]').fill(v);
  await panel.locator('[data-edit-key="lum"]').uncheck();
  await panel.locator('[data-assignment-role="MARCEL"][data-assignment-field="microphone"]').selectOption('DPA 4088 #2');
  await panel.locator('[data-assignment-role="MARCEL"][data-assignment-field="iem"]').selectOption('PSM 900 #2');
  await panel.getByRole('button',{name:'Enregistrer',exact:true}).click();await page.waitForFunction(()=>!document.getElementById('cue-panel').open);
  const updated=document.cues.find(c=>String(c.number)==='50');
  for(const [k,v] of Object.entries(changes))assert.equal(updated[k],v,k);
  assert.equal(updated.lum,false);assert.equal(updated.role_assignments.DIRECTRICE.microphone,'DPA 4088 #3');assert.equal(updated.role_assignments.MARCEL.microphone,'DPA 4088 #2');assert.equal(updated.role_assignments.MARCEL.iem,'PSM 900 #2');
  assert.equal(document.cues.find(c=>String(c.number)==='52').microphone,'');
  await page.locator('#filter-section').selectOption('ENTRACTE');await page.waitForTimeout(100);
  assert.ok(await page.locator('.ce-cue').count()>0);assert.equal(await row(48).count(),0);
  await page.locator('#filter-section').selectOption('');await page.waitForTimeout(100);
  await page.getByRole('button',{name:'Sélectionner',exact:true}).click();await row(48).getByRole('checkbox').check();
  assert.equal(await page.locator('#builder-bulk-role-bar').isVisible(),true);
  await page.locator('#builder-bulk-role-bar').getByRole('button',{name:'AUCUN',exact:true}).click();await page.waitForTimeout(100);
  assert.equal(await page.locator('#builder-bulk-role-bar').isVisible(),false);
  const countBeforeNew=document.cues.length;
  await page.getByRole('button',{name:'+ CUE',exact:true}).click();
  await page.locator('#cue-panel [data-edit-key="text"]').fill('Cue ajouté en test isolé');
  await page.locator('#cue-panel').getByRole('button',{name:'Enregistrer',exact:true}).click();
  await page.waitForFunction(()=>!document.getElementById('cue-panel').open);
  assert.equal(document.cues.length,countBeforeNew+1);
  assert.equal(document.cues.find(c=>c.text==='Cue ajouté en test isolé').role,'');
  if(process.env.SHOWCUE_SCREENSHOTS){
    document=structuredClone(originalDocument);await page.reload();await page.waitForFunction(()=>document.querySelectorAll('.ce-cue').length>0);await page.waitForTimeout(1100);
    await row(48).scrollIntoViewIfNeeded();await page.screenshot({path:path.join(process.env.SHOWCUE_SCREENSHOTS,'cue-editor-desktop.png')});
  }
  await page.setViewportSize({width:390,height:844});await page.waitForTimeout(150);
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'no horizontal page overflow');
  const box=await row(52).boundingBox();assert.ok(box.width<=390);
  await row(52).getByRole('button',{name:'Modifier',exact:true}).click();
  const footer=await page.locator('.ce-panel-footer').boundingBox();assert.ok(footer.y+footer.height<=844,'save actions fit mobile viewport');
  if(process.env.SHOWCUE_SCREENSHOTS)await page.screenshot({path:path.join(process.env.SHOWCUE_SCREENSHOTS,'cue-editor-mobile-edition.png')});
  await page.locator('#cue-panel').getByRole('button',{name:'Annuler'}).click();
  if(process.env.SHOWCUE_SCREENSHOTS){await row(48).evaluate(n=>n.scrollIntoView({block:'start'}));await page.screenshot({path:path.join(process.env.SHOWCUE_SCREENSHOTS,'cue-editor-mobile.png')});}
  if(process.env.SHOWCUE_SCREENSHOTS){
    await row(52).getByRole('button',{name:'Détails',exact:true}).click();
    await page.screenshot({path:path.join(process.env.SHOWCUE_SCREENSHOTS,'cue-editor-mobile-details.png')});
  }
  if(process.env.SHOWCUE_TEST_PAYLOAD)fs.writeFileSync(process.env.SHOWCUE_TEST_PAYLOAD,JSON.stringify(writes[0].document));
  assert.deepEqual(errors,[],'browser JS errors');
  await page.close();
 }finally{await browser.close();}
});
