const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{execFileSync}=require('child_process');
const source=process.env.CONSOLE_PANEL_SOURCE||path.resolve(__dirname,'../../launcher_control.py');
const html=execFileSync('python3',['-c',"import ast,sys; t=ast.parse(open(sys.argv[1]).read()); print(ast.literal_eval(next(n.value for n in t.body if isinstance(n,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='PANEL_HTML_V2' for x in n.targets))))",source],{encoding:'utf8'});
const out=process.env.CONSOLE_TEST_OUTPUT||path.join(require('os').tmpdir(),'cl-console-health-ui');fs.mkdirSync(out,{recursive:true});
const fixture=()=>{const now=Date.now()/1000;return {local_url:'http://127.0.0.1:5050/',web:true,server_valid:true,system_ready:true,events:[],ltc_destination:'127.0.0.1',ltc_port:63123,midi_console:{updated_at:now,online:true,return_mode:'local_dedicated',return_monitor_status:0,return_monitor_source:'CL MIDI Return Test'},devices:['cl5','ql1'].map((name,i)=>({id:i?'console_b':'console_a',legacy_key:name,display_name:name.toUpperCase(),enabled:true,production_supported:true,library:name,midi_channel:i+1,expected_midi_program:13,returned_midi_program:13,expected_scene_memory:14,returned_scene_memory:14,expected_title:'FALLING',returned_title:'FALLING',expected_activated_at:now-.3,returned_at:now-.12,confirmation_latency_ms:180,palette:{base:i?'#88e9fa':'#ff9dd9',accent:i?'#37cce9':'#ed56b6'}}))};};
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});const ctx=await browser.newContext({viewport:{width:500,height:900}});let state=fixture(),offline=false,actions=[],errors=[];
await ctx.route('**/*',r=>{const u=new URL(r.request().url());if(u.hostname!=='panel.invalid')return r.abort();if(u.pathname==='/')return r.fulfill({body:html,contentType:'text/html'});if(u.pathname==='/state')return offline?r.abort():r.fulfill({json:state});if(u.pathname==='/telemetry')return r.fulfill({json:{}});if(u.pathname==='/midi-network-assistant'){actions.push(u.pathname);return r.fulfill({json:{message:'Ouverture simulée'}});}return r.fulfill({json:{}});});
const p=await ctx.newPage();p.on('pageerror',e=>errors.push(e.message));await p.goto('https://panel.invalid/');
const apply=async s=>{state=s;await p.evaluate(s=>render(s),s);};
await p.waitForFunction(()=>document.getElementById('consoleHealth').classList.contains('ok'));
assert.match(await p.locator('#cl5Return').innerText(),/PC 13.*Scène 14/);assert.match(await p.locator('#cl5Return').innerText(),/180 ms/);
assert.equal(await p.locator('summary').filter({hasText:'Détails techniques et événements'}).evaluate(e=>e.parentElement.open),false);
await p.locator('.console-card').screenshot({path:path.join(out,'ok.png')});
for(const kind of ['waiting','mismatch','stale','stale-different','offline','endpoint','null']){
 let s=fixture();if(kind==='waiting')s.devices.forEach(d=>{d.returned_at=null;d.returned_midi_program=null;d.returned_scene_memory=null;d.returned_title='';});
 if(kind==='mismatch')s.devices[0].returned_midi_program=43;
 if(kind.startsWith('stale'))s.devices.forEach(d=>{d.returned_at-=18*3600;d.validation_status='confirmed';});
 if(kind==='stale-different')s.devices[0].returned_midi_program=43;
 if(kind==='offline')s.midi_console.updated_at-=20;
 if(kind==='endpoint')s.midi_console.return_monitor_status=-10834;
 if(kind==='null'){s.midi_console=null;s.devices=[null];}
 await apply(s);const level=await p.locator('#consoleHealth').getAttribute('class');assert.match(level,['offline','endpoint','null'].includes(kind)?/error/:/warning/);
 if(kind==='stale'){assert.match(await p.locator('#cl5Return').innerText(),/Retour ancien · conforme/);assert.equal(await p.locator('#consoleHealthTitle').innerText(),'BACKEND ACTIF · RETOUR ANCIEN');}
 if(kind==='stale-different')assert.match(await p.locator('#cl5Return').innerText(),/Retour ancien · différent/);
 if(kind==='waiting')assert.match(await p.locator('#cl5Return').innerText(),/En attente de retour/);
 if(kind==='mismatch')assert.match(await p.locator('#cl5Return').innerText(),/Retour différent/);
 assert.equal(await p.locator('#consoleManager').evaluate(e=>e.classList.contains('corrective')),true);
 await p.locator('.console-card').screenshot({path:path.join(out,kind+'.png')});
}
await apply(fixture());await p.locator('#consoleManager').click();assert.deepEqual(actions,['/midi-network-assistant']);
await apply(fixture());offline=true;await p.evaluate(()=>refresh());assert.match(await p.locator('#consoleHealth').getAttribute('class'),/error/);assert.match(await p.locator('#cl5Return .console-state').innerText(),/Indisponible/);offline=false;
for(const width of [390,500,1200]){await p.setViewportSize({width,height:900});await apply(fixture());assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await p.locator('#consoleManager').scrollIntoViewIfNeeded();const buttonHeight=(await p.locator('#consoleManager').boundingBox()).height;assert.ok(buttonHeight>=38&&buttonHeight<=42);console.log('HEIGHT',width,(await p.locator('.console-card').boundingBox()).height);}
assert.deepEqual(errors,[]);await browser.close();console.log('PASS UI: OK/warning/unavailable, mismatch, 18h old, null, transport failure, actual manager button, closed details, 390/500/1200 widths');
})().catch(e=>{console.error(e);process.exit(1);});
