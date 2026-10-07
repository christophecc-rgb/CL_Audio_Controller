// Real panel functions, synthetic Bonjour responses, no browser/LAN/config writes.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync(require('path').resolve(__dirname,'../../launcher_control.py'),'utf8');
const section=(a,b)=>source.slice(source.indexOf(a),source.indexOf(b,source.indexOf(a)));
const nodes=new Map();
const el=id=>{if(!nodes.has(id))nodes.set(id,{value:'',textContent:'',children:[],options:new Map(),querySelector(selector){if(!this.options.has(selector))this.options.set(selector,{textContent:''});return this.options.get(selector)},replaceChildren(){this.children=[]},appendChild(n){this.children.push(n)}});return nodes.get(id)};
const ctx=vm.createContext({el,document:{createElement:()=>({})},console,Date});
vm.runInContext('let latestState={cl_server:{mode:"paradis",remote:false}},networkDrafts={},networkVisibleMode,networkFormDirty=false,networkFormInitialized=false;'+section('// ABLETON_DISCOVERY_BEGIN','// ABLETON_DISCOVERY_END')+section('function copyNetworkDraft(','async function saveNetworkConfig()'),ctx);
const call=code=>vm.runInContext(code,ctx);
const reader={host:'iMac-de-Sono-2.local',addresses:['192.168.1.53'],interfaces:['en0'],port:11000,state:'resolved'};
ctx.data={local_host:'Mac-Test.local',service:'_cl-ableton._udp',readers:[reader],refreshed_at:1234};
call('initializeNetworkForm({ableton_profiles:{local:{host:"127.0.0.1"},remote:{host:"manual.local"}},ableton_active_mode:"local"})');
call('renderAbletonReaders(data);selectAbletonReader("iMac-de-Sono-2.local:11000")');
assert.equal(el('clServerMode').querySelector('[value=local]').textContent,'Mac-Test.local');
assert.equal(el('abletonMode').querySelector('[value=local]').textContent,'Mac-Test.local');
assert.equal(el('abletonHost').value,'127.0.0.1');assert.equal(el('abletonReaders').disabled,true);
assert.equal(el('abletonDiscovery').hidden,true);
el('abletonMode').value='remote';call('updateNetworkFields();renderAbletonReaders(data)');
assert.equal(el('abletonHost').value,'manual.local'); // discovery cannot auto-switch
assert.equal(el('abletonDiscovery').hidden,false);
call('selectAbletonReader("iMac-de-Sono-2.local:11000")');
assert.equal(el('abletonHost').value,reader.host);
assert.equal(el('abletonDiscoveryStatus').textContent,'Adresse sélectionnée — cliquez sur Appliquer, puis Tester la connexion');
assert.equal(call('networkDrafts.remote.host'),reader.host);assert.equal(call('networkFormDirty'),true);
assert.equal(call('latestState.cl_server.mode'),'paradis'); // CL profile is independent
assert.equal(call('networkDrafts.local.host'),'127.0.0.1');
call('renderAbletonReaders({...data,readers:[]})');
assert.equal(el('abletonHost').value,reader.host);assert.equal(el('abletonReaders').children.length,1);
assert.equal(el('abletonDiscoveryStatus').textContent,'Aucun Mac Ableton détecté — saisissez son adresse manuellement');
assert.equal(el('abletonReaders').children[0].textContent,el('abletonDiscoveryStatus').textContent);
call('selectAbletonReader("iMac-de-Sono-2.local:11000")');assert.equal(el('abletonHost').value,reader.host);
el('abletonHost').value='manual.example';call('markNetworkDraftDirty()');
assert.equal(call('networkDrafts.remote.host'),'manual.example');
ctx.data.readers=[{...reader,state:'discovered',addresses:[]}];call('renderAbletonReaders(data);selectAbletonReader("iMac-de-Sono-2.local:11000")');
assert.equal(el('abletonHost').value,'manual.example');
ctx.data.readers=[{...reader,port:12000}];call('renderAbletonReaders(data);selectAbletonReader("iMac-de-Sono-2.local:12000")');
assert.equal(el('abletonHost').value,'manual.example');
ctx.data.readers=[reader];call('latestState.cl_server.remote=true;renderAbletonReaders(data);selectAbletonReader("iMac-de-Sono-2.local:11000")');
assert.equal(el('abletonReaders').disabled,true);assert.equal(el('abletonHost').value,'manual.example');
assert.equal(el('abletonDiscovery').hidden,true);
call('latestState.cl_server.remote=false');
el('abletonMode').value='local';call('updateNetworkFields()');
assert.equal(el('abletonDiscovery').hidden,true);assert.equal(el('abletonHost').value,'127.0.0.1');
assert.match(source,/La détection nécessite une annonce réseau Bonjour active/);
assert.match(source,/Un Mac non détecté peut avoir Ableton ouvert et rester accessible/);
// No fetch exists in this context: any hidden application or OSC request fails.
console.log('PASS: explicit selection only, hostname retained, Local/Paradis/manual preserved, removal and remote backend lock.');
