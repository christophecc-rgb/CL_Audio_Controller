const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{execFileSync}=require('child_process');
const source=process.env.CONSOLE_PANEL_SOURCE||path.resolve(__dirname,'../../launcher_control.py');
const html=execFileSync('python3',['-c',"import ast,sys; t=ast.parse(open(sys.argv[1]).read()); print(ast.literal_eval(next(n.value for n in t.body if isinstance(n,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='PANEL_HTML_V2' for x in n.targets))))",source],{encoding:'utf8'});
const out=process.env.PARADIS_TEST_OUTPUT||path.join(require('os').tmpdir(),'cl-paradis-ui');fs.mkdirSync(out,{recursive:true});
const local={mode:'local',host:'127.0.0.1',send_port:11000,reply_port:11001};
const remote={mode:'remote',host:'iMac-de-Sono-2.local',send_port:11000,reply_port:11001};
let choice={mode:'local',host:''},posts=[],errors=[];
function fixture(){const distant=choice.mode!=='local';return {web:true,server_valid:true,system_ready:true,events:[],devices:[],ableton_active_mode:distant?'remote':'local',ableton_profiles:{local,remote},ableton_config:distant?remote:local,ableton_server_target:distant?remote:local,cl_server:{mode:choice.mode,remote:distant,server:distant?'iMac Record Blue':'Ce Mac',hostname:choice.mode==='manual'?choice.host:(distant?'iMac-Record-Blue.local':'localhost'),address:distant?'192.168.3.64':'127.0.0.1',discovery:distant?'Nom résolu':'Serveur local',validation:'Serveur CL validé',network:distant?'Contrôle câblé':'Local',server_valid:true},midi_console:{},local_url:'http://127.0.0.1:5050/'};}
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
 try{
 const ctx=await browser.newContext({viewport:{width:500,height:900}});
 await ctx.route('**/*',r=>{const u=new URL(r.request().url());if(u.hostname!=='paradis.invalid')return r.abort();if(u.pathname==='/')return r.fulfill({body:html,contentType:'text/html'});if(u.pathname==='/state')return r.fulfill({json:fixture()});if(u.pathname==='/network-config'){posts.push(r.request().postDataJSON());choice=posts.at(-1).cl_server;return r.fulfill({json:{message:'Choix enregistré'}});}return r.fulfill({json:{}});});
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));
 await page.goto('https://paradis.invalid/');await page.waitForFunction(()=>document.querySelector('#clServerDiagnostic').textContent.includes('127.0.0.1'));
 assert(await page.locator('#abletonHost').isDisabled());
 await page.selectOption('#clServerMode','paradis');await page.getByRole('button',{name:'Appliquer / Rechercher',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('#clServerDiagnostic').textContent.includes('192.168.3.64'));
 assert.deepEqual(posts[0],{cl_server:{mode:'paradis',host:''}});
 assert(await page.locator('#abletonMode').isDisabled());
 assert((await page.locator('#clServerDiagnostic').innerText()).includes('iMac-de-Sono-2.local'));
 for(const width of [390,500,1200]){await page.setViewportSize({width,height:900});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.locator('#clServerDiagnostic').locator('..').screenshot({path:path.join(out,`paradis-${width}.png`)});}
 await page.selectOption('#clServerMode','manual');assert(await page.locator('#clServerHost').isEnabled());await page.fill('#clServerHost','iMac-Record-Blue.local');await page.getByRole('button',{name:'Appliquer / Rechercher',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#clServerMode').value==='manual'&&!clServerDirty);
 await page.reload();await page.waitForFunction(()=>document.querySelector('#clServerMode').value==='manual');assert.equal(await page.inputValue('#clServerHost'),'iMac-Record-Blue.local');
 await page.selectOption('#clServerMode','local');await page.getByRole('button',{name:'Appliquer / Rechercher',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#clServerDiagnostic').textContent.includes('127.0.0.1'));
 assert(await page.locator('#abletonMode').isEnabled());assert(await page.locator('#abletonHost').isDisabled());assert.deepEqual(errors,[]);
 console.log('PASS: Local / Paradis Latin / Distant manuel, isolated server payload, persisted selection, remote OSC disabled, loopback locked, widths 390/500/1200, no JS errors');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
