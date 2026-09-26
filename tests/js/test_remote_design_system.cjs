// Offline visual regression: never connects to Ableton or a running server.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{execFileSync}=require('child_process');
const repo=path.resolve(__dirname,'../..'),overlay=process.env.GLOBAL_OVERLAY||repo,out=process.env.SKIN_TEST_OUTPUT||path.join(require('os').tmpdir(),'cl-remote-design-tests');fs.mkdirSync(out,{recursive:true});
const read=f=>fs.readFileSync(fs.existsSync(path.join(overlay,f))?path.join(overlay,f):path.join(repo,f));
const html=JSON.parse(execFileSync('python3',[path.join(__dirname,'render_remote_fixture.py'),repo,overlay]));
const base=module=>({set_generation:1,connected:true,message:'Ableton connecté · simulation',play_mode:module==='arrangement'?'arrangement':'session',is_playing:true,is_paused:false,has_show_started:true,playing_scene:0,last_fired_scene:0,selected_scene:1,scenes:{0:'FREE FROM DESIRE;120;03:00',1:'FIN END;120;00:18',2:'NOIR;120;00:30'},selected_scene_name:'FIN END;120;00:18',remaining_seconds:24,remaining_time:'00:24',scene_duration_seconds:180,arrangement_time:36,arrangement_marker:'FREE FROM DESIRE',expected_activated_at:1,arrangement_markers:[{name:'FREE FROM DESIRE',time:0,source:'live',cue_index:0},{name:'FIN END',time:60,source:'live',cue_index:1},{name:'NOIR',time:78,source:'live',cue_index:2}],ltc_connected:true,ltc_timecode:'01:02:03:04',crossfader:-1,devices:[{id:'console_a',display_name:'CL5',production_supported:true,library:'cl5',visual_state:'idle',validation_status:'unavailable',expected_scene_memory:12,returned_scene_memory:12,expected_title:'Ouverture',returned_title:'Ouverture',palette:{base:'#c09af2',accent:'#9b6bd6'}},{id:'console_b',display_name:'QL1',production_supported:true,library:'ql1',visual_state:'idle',validation_status:'unavailable',expected_scene_memory:8,returned_scene_memory:8,expected_title:'Ouverture',returned_title:'Ouverture',palette:{base:'#63c7d4',accent:'#3e9eac'}}]});
(async()=>{const b=await chromium.launch({headless:true,...(process.env.CHROME_PATH ? {executablePath:process.env.CHROME_PATH} : {})});const c=await b.newContext();let states={},actions=[],errors=[],results=[];
await c.route('**/*',r=>{const u=new URL(r.request().url());if(u.hostname!=='audit.invalid')return r.abort();if(html[u.pathname])return r.fulfill({body:html[u.pathname],contentType:'text/html'});if(u.pathname==='/status')return r.fulfill({json:states[new URL(r.request().frame().url()).pathname]});if(u.pathname==='/keyboard-log')return r.fulfill({json:{ok:true}});if(u.pathname==='/action'){const a=r.request().postDataJSON(),route=new URL(r.request().frame().url()).pathname;actions.push({route,...a});return r.fulfill({json:{ok:true,go_confirmed:true,state:states[route]}});}if(u.pathname.startsWith('/static/')||u.pathname.startsWith('/assets/')){try{return r.fulfill({body:read(decodeURIComponent(u.pathname.slice(1))),contentType:u.pathname.endsWith('.css')?'text/css':u.pathname.endsWith('.js')?'text/javascript':'image/jpeg'});}catch{return r.fulfill({status:404,body:''});}}return r.abort();});
const p=await c.newPage();p.on('pageerror',e=>errors.push(e.message));
const css=(sel,pseudo)=>p.$eval(sel,(e,ps)=>{const s=getComputedStyle(e,ps);return{animation:s.animationName,opacity:s.opacity,background:s.backgroundImage,shadow:s.boxShadow,clip:s.clip,transform:s.transform,visibility:s.visibility};},pseudo);
for(const [route,module]of [['/','session'],['/ab','ab'],['/arrangement','arrangement']]){
 states[route]=base(module);await p.goto('https://audit.invalid'+route);await p.waitForSelector('#sessionSkin',{state:'attached'});await p.waitForFunction(()=>document.querySelector('.sc-current').dataset.uiState==='playing');
 const apply=async patch=>{states[route]={...states[route],...patch};await p.evaluate(s=>applyStatus(s),states[route]);};
 for(const skin of ['original','broadcast','theatre','show-control','neon']){
  await p.locator('details').evaluate(e=>e.open=true);const n=actions.length;
  const before=await p.evaluate(()=>[...document.querySelectorAll('[id]')].map(e=>e.id));
  await p.selectOption('#sessionSkin',skin);await p.waitForTimeout(250);assert.equal(actions.length,n);assert.deepEqual(await p.evaluate(()=>[...document.querySelectorAll('[id]')].map(e=>e.id)),before);
  await p.locator('details').evaluate(e=>e.open=false);
  for(const [mode,patch]of [['paused',{is_playing:false,is_paused:true}],['stopped',{is_playing:false,is_paused:false,playing_scene:-1,last_fired_scene:-1,has_show_started:false}],['playing',{is_playing:true,is_paused:false,playing_scene:0,last_fired_scene:0,has_show_started:true}]]){
   if(module==='session'&&mode==='stopped')await p.evaluate(()=>{sessionWasPlaying=false;});
   await apply(patch);await p.waitForFunction(mode=>document.querySelector('.sc-current').dataset.uiState===mode,mode);
   if(mode!=='playing') {
    await p.waitForFunction(()=>{const a=document.querySelector('.cl-current-flow-layer')._clFlowAnimation;return a&&a.playState==='paused'&&!a.pending;});
    const frozen=await p.locator('.cl-current-flow-layer').evaluate(e=>e._clFlowAnimation.currentTime);
    await p.waitForTimeout(90);
    assert.equal(await p.locator('.cl-current-flow-layer').evaluate(e=>e._clFlowAnimation.currentTime),frozen);
   }

   if(skin!=='original') {const v=await css('.sc-current');assert.equal(v.background,'none');assert.ok(skin==='neon'||v.shadow==='none'||v.shadow.startsWith('rgba(0, 0, 0,'),`${module}/${skin}: colored permanent glow ${v.shadow}`);if(mode==='playing')assert.match((await css('.sc-current','::before')).animation,/sc-live/);}
  }
  if(module==='session')await p.evaluate(()=>pulseSelectedCard());
  if(module==='ab')await p.selectOption('#abSceneSelect','2');
  if(module==='arrangement')await p.selectOption('#markerSelect','1');
  await p.waitForFunction(()=>document.querySelector('.sc-next').dataset.uiState==='ready');
  if(skin!=='original')assert.match((await css('.sc-next','::before')).animation,/sc-ready/);
  if(module==='ab'){
   await p.evaluate(()=>{userSceneChoiceDirty=false;});await apply({remaining_seconds:5});await p.waitForFunction(()=>document.querySelector('.sc-next').dataset.uiState==='imminent');
   await apply({remaining_seconds:24,crossfader:1});await p.waitForFunction(()=>document.querySelector('.v2-app').dataset.uiDeck==='b');
   await apply({crossfader:-1});
  }else{
   await apply({ltc_connected:false});assert.equal(await p.locator('#ltcTimecode').textContent(),'--:--:--:--');await apply({ltc_connected:true});
   for(const phase of ['idle','waiting','confirmed','loaded','mismatch','timeout']){
    await p.evaluate(phase=>document.querySelectorAll('.midi-return').forEach(e=>e.className='midi-return state-'+phase+(phase==='waiting'?' recall-pulse':'')),phase);
    if(skin!=='original'&&phase==='mismatch')assert.equal((await css('.midi-return')).animation,'none');
    if(skin!=='original'&&phase==='confirmed')assert.equal((await css('.midi-return')).animation,'none');
   }
  }
  await apply({connected:false,message:'Interface non connectée'});await p.waitForFunction(()=>document.querySelector('.sc-current').dataset.uiState==='offline');await apply({connected:true,message:'Ableton connecté · simulation'});
  if(module==='session'){await apply({expected_activated_at:states[route].expected_activated_at+1});await p.waitForFunction(()=>document.querySelector('.sc-current').classList.contains('session-recall-pulse'));if(skin!=='original')assert.match((await css('.sc-current','::after')).animation,/sc-go/);}
  for(const [w,h]of [[1440,900],[1024,768],[768,1024],[390,844],[320,568],[844,390],[667,375]]){
   await p.setViewportSize({width:w,height:h});await p.waitForFunction(()=>document.querySelector('.sc-current').dataset.uiState==='playing');
   const boxes=await p.evaluate(()=>{const rec=e=>{const r=e.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom};};return{viewport:innerWidth,scroll:document.documentElement.scrollWidth,current:rec(document.querySelector('.sc-current')),next:rec(document.querySelector('.sc-next')),timer:rec(document.querySelector('.sc-current .sc-time')),header:rec(document.querySelector('.sc-current .sc-card-header')),footer:rec(document.querySelector('.sc-current .sc-card-footer')),deck:document.querySelector('.deck-screen')?rec(document.querySelector('.deck-screen')):null,midi:document.querySelector('.midi-returns')?rec(document.querySelector('.midi-returns')):null,buttons:[...document.querySelectorAll('button')].filter(e=>e.offsetParent&&!e.closest('details')).map(e=>({id:e.id, ...rec(e)}))};});
   assert.ok(boxes.scroll<=w,`${module}/${skin}/${w}: page overflow`);
   if(skin!=='original'){assert.ok(boxes.current.width>200,`${module}/${skin}/${w}: card width`);if (module === 'ab') {
  assert.ok(boxes.timer.width > 30, `${module}/${skin}/${w}: timer visible`);
} else {
  assert.equal(boxes.timer.width, 0, `${module}/${skin}/${w}: duplicate header timer hidden`);
  assert.equal(boxes.timer.height, 0, `${module}/${skin}/${w}: duplicate header timer hidden`);
}assert.ok(boxes.header.y>=boxes.current.y&&boxes.footer.bottom<=boxes.current.bottom,`${module}/${skin}/${w}: clipped header/footer`);if(boxes.deck)assert.ok(boxes.current.y>=boxes.deck.y,`${module}/${skin}/${w}: clipped deck`);for(const button of boxes.buttons)assert.ok(button.width>=44&&button.height>=44,`${module}/${skin}/${w}: target ${button.id} ${button.width}x${button.height}`);if(boxes.midi)assert.ok(boxes.midi.width>w*.6);}
   // Test real controls, including the native desktop wrapper's query flag.
   if(w===390 || w===1440) {
    await p.locator('details').evaluate(e=>e.open=true);
    await p.locator('#visual-goRelief').scrollIntoViewIfNeeded();
    assert.ok(await p.locator('#visual-goRelief').evaluate(e=>{const r=e.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight;}),`${module}/${skin}: preferences unreachable`);
    const actionCount=actions.length;
    await p.selectOption('#visual-flowIntensity','high');
    assert.equal(await p.locator('body').getAttribute('data-flow-intensity'),'high');
    await p.waitForTimeout(300);assert.equal(await p.locator('.cl-current-flow-layer').evaluate(e=>getComputedStyle(e).opacity),'1');
    for(const value of ['sober','halo','wave','luminous']) {
      await p.selectOption('#visual-currentStyle',value);
      assert.equal(await p.locator('body').getAttribute('data-current-style'),value);
    }
    await p.selectOption('#visual-visualAnimation','off');await p.waitForTimeout(60);
    const flowTime=()=>p.locator('.cl-current-flow-layer').evaluate(e=>e._clFlowAnimation.currentTime);
    await p.waitForFunction(()=>{const a=document.querySelector('.cl-current-flow-layer')._clFlowAnimation;return a.playState==='paused'&&!a.pending;});const frozen=await flowTime();await p.waitForTimeout(80);assert.equal(await flowTime(),frozen);
    await p.selectOption('#visual-visualAnimation','soft');await p.waitForTimeout(60);
    assert.equal(await p.locator('.cl-current-flow-layer').evaluate(e=>e._clFlowAnimation.playbackRate),.5);
    for(const relief of ['flat','light','3d']) {
      await p.selectOption('#visual-goRelief',relief);await p.waitForTimeout(200);
      const shadow=await p.locator('.go-button,#abSceneConfirm,#goBtn').first().evaluate(e=>getComputedStyle(e).boxShadow);
      assert.equal(shadow==='none',relief==='flat',`${module}/${skin}/${relief}: relief not applied`);
    }
    assert.equal(await p.locator('body').getAttribute('data-go-relief'),'3d');
    assert.equal(actions.length,actionCount,'visual control sent an action');
    await p.locator('.cl-visual-reset').click();
    assert.equal(await p.locator('body').getAttribute('data-go-relief'),'default');
    await p.locator('details').evaluate(e=>e.open=false);
   }
   results.push({module,skin,viewport:`${w}x${h}`,boxes});
   await p.evaluate(()=>window.scrollTo(0,0));
   if([1440,390,844].includes(w))await p.screenshot({path:path.join(out,`${module}-${skin}-${w}.png`),fullPage:true});
  }
 }
}
// A single preference travels through real shell links, including protected Arrangement navigation.
await p.locator('details').evaluate(e=>e.open=true);await p.selectOption('#sessionSkin','show-control');
await p.locator('.v2-tabs a[href="/"]').click();await p.waitForFunction(()=>document.body.dataset.skin==='show-control');
await p.locator('.v2-tabs a[href="/ab"]').click();await p.waitForFunction(()=>document.body.dataset.skin==='show-control');
p.once('dialog',d=>d.accept());await p.locator('.v2-tabs a[href="/arrangement"]').click();await p.waitForFunction(()=>document.querySelector('.v2-app').dataset.module==='arrangement');assert.equal(await p.locator('body').getAttribute('data-skin'),'show-control');assert.ok(actions.some(a=>a.action==='back_to_arrangement'));
await p.locator('details').evaluate(e=>e.open=true);
await p.selectOption('#sessionSkin','neon');await p.selectOption('#visual-goRelief','flat');
await p.reload();await p.waitForFunction(()=>document.body.dataset.skin==='neon'&&document.body.dataset.goRelief==='flat');
const second=await c.newPage();await second.goto('https://audit.invalid/ab?desktop=1');
await second.waitForFunction(()=>document.body.dataset.skin==='neon'&&document.body.dataset.goRelief==='flat');
await p.locator('details').evaluate(e=>e.open=true);await p.selectOption('#sessionSkin','original');
await second.waitForFunction(()=>document.body.dataset.skin==='original');
await second.locator('details').evaluate(e=>e.open=true);
await second.locator('#visual-goRelief').scrollIntoViewIfNeeded();
assert.ok(await second.locator('#visual-goRelief').evaluate(e=>{const r=e.getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight;}));
await second.close();
assert.deepEqual(errors,[]);fs.writeFileSync(path.join(out,'results.json'),JSON.stringify({results,errors,actions},null,2));await b.close();console.log('PASS',results.length,'view/skin/viewport cases, all three views and global navigation');
})().catch(e=>{console.error(e);process.exit(1);});
