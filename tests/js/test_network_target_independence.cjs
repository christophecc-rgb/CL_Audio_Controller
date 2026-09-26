// Exercise the real panel functions with a minimal DOM and isolated HTTP fixture.
const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync(process.env.CONSOLE_PANEL_SOURCE||path.resolve(__dirname,'../../launcher_control.py'),'utf8');
const section=(a,b)=>source.slice(source.indexOf(a),source.indexOf(b,source.indexOf(a)));
const nodes=new Map();
const el=id=>{if(!nodes.has(id))nodes.set(id,{value:'',textContent:'',className:'',children:[]});return nodes.get(id)};
const local={mode:'local',host:'127.0.0.1',send_port:11000,reply_port:11001};
const remote={mode:'remote',host:'192.168.1.53',send_port:11000,reply_port:11001};
let active='local',posts=[];
const fixture=()=>({ableton_profiles:{local,remote},ableton_active_mode:active,
 ableton_server_target:{...local}, // Old process deliberately disagrees with saved remote target.
 ableton_config:active==='remote'?remote:local,events:[],midi_console:{}});
const context=vm.createContext({el,console,setTimeout:fn=>fn(),
 setTech(){},updateShowCurrent(){},showDevicesForState:()=>[],syncShowDeviceDom(){},renderConsoleHealth:()=>({cards:[]}),renderCLServer(){},
 fetch:async(url,opts)=>{const p=JSON.parse(opts.body);posts.push(p);if(!p.cl_server){active=p.mode;assert.equal(p.host,active==='remote'?'192.168.1.53':'127.0.0.1')}return {ok:true,json:async()=>({message:'OK'})}}});
vm.runInContext(`let latestState,networkDrafts={},networkVisibleMode,networkFormDirty=false,networkFormInitialized=false,clServerDirty=false,clServerInitialized=false;\n`+
 section('function render(s){','async function refresh()')+
 section('function copyNetworkDraft(','async function testAbletonConnection()')+
 section('async function saveCLServer(){','function renderCLServer(s)')+
 'async function refresh(){render(fixture())}',context);
context.fixture=fixture;
(async()=>{
 for(const mode of ['local','remote','local','remote']){
  vm.runInContext('render(fixture())',context);
  el('abletonMode').value=mode;
  vm.runInContext('updateNetworkFields();render(fixture())',context);
  assert.equal(el('abletonHost').value,mode==='remote'?'192.168.1.53':'127.0.0.1');
  await vm.runInContext('saveNetworkConfig()',context);
  vm.runInContext('render(fixture())',context);
  assert.equal(el('abletonHost').value,mode==='remote'?'192.168.1.53':'127.0.0.1');
 }
 for(const mode of ['paradis','manual','local']){
  el('clServerMode').value=mode;el('clServerHost').value=mode==='manual'?'192.168.3.64':'';
  await vm.runInContext('saveCLServer()',context);
  assert.equal(el('abletonHost').value,'192.168.1.53');
  assert.equal(el('abletonMode').value,'remote');
  assert.deepEqual(Object.keys(posts.at(-1)),['cl_server']);
 }
 console.log('PASS: panel Local → Distant → Local → Distant; stale backend cannot overwrite saved host; server switches preserve target.');
})().catch(e=>{console.error(e);process.exitCode=1});
