// Offline tests: extracts presentation helpers without importing or starting the launcher.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const source=fs.readFileSync(process.env.CONSOLE_PANEL_SOURCE||path.join(__dirname,'../../launcher_control.py'),'utf8');
const helper=source.split('// CONSOLE_HEALTH_BEGIN')[1].split('// CONSOLE_HEALTH_END')[0];
const ctx=vm.createContext({});vm.runInContext('// CONSOLE_HEALTH_BEGIN'+helper,ctx);
const health=(state,devices)=>ctx.consoleHealth(state,devices,1000);
const state={midi_console:{online:true,updated_at:1000,return_monitor_status:0,return_monitor_source:'CL MIDI Return Test',return_mode:'local_dedicated'}};
const devices=['cl5','ql1'].map((legacy,i)=>({id:i?'console_b':'console_a',legacy_key:legacy,production_supported:true,midi_channel:i+1,expected_midi_program:13,returned_midi_program:13,expected_scene_memory:14,returned_scene_memory:14,expected_activated_at:999,returned_at:999.18,confirmation_latency_ms:180}));
assert.equal(health(state,devices).level,'ok');assert.equal(health(state,devices).cards[0].latency,180);
for(const value of [null,undefined,{}, {midi_console:null}])assert.equal(health(value,[]).level,'error');
for(const patch of [{online:false},{updated_at:990},{return_monitor_status:-10834},{return_monitor_status:null},{return_monitor_source:''},{return_mode:'local_fallback'}]) {
 const s={midi_console:{...state.midi_console,...patch}};assert.equal(health(s,devices).level,'error',JSON.stringify(patch));
}
for(const device of [
 {...devices[0],returned_at:1000-18*3600},
 {...devices[0],expected_activated_at:999.5,returned_at:999},
 {...devices[0],returned_at:960,validation_status:'confirmed'},
])assert.notEqual(health(state,[device,devices[1]]).level,'ok');
let result=health(state,devices.map(d=>({...d,returned_at:null,returned_midi_program:null})));
assert.equal(result.level,'warning');assert.match(result.title,/AUCUN RETOUR/);assert.doesNotMatch(result.title,/SIMULATEURS ARRÊTÉS/);
result=health(state,[{...devices[0],returned_midi_program:43},devices[1]]);assert.equal(result.cards[0].status,'mismatch');assert.equal(result.level,'warning');
result=health(state,devices.map(d=>({...d,returned_at:950})));assert.equal(result.cards[0].status,'stale');assert.equal(result.level,'warning');
assert.equal(health(state,devices.map(d=>({...d,expected_activated_at:null}))).level,'warning');
assert.equal(health(state,devices.map(d=>({...d,expected_midi_program:0,returned_midi_program:0}))).level,'ok');
assert.equal(health(state,devices.map(d=>({...d,expected_midi_program:null}))).level,'warning');
assert.equal(health(state,devices.map(d=>({...d,returned_at:1010}))).level,'warning');
console.log('PASS console health: null, missing monitor/endpoint, OK, waiting, mismatch, stale, old matching, PC 0, missing intent, future clock');

result=health(state,devices.map(d=>({...d,returned_at:950})));assert.equal(result.title,'BACKEND ACTIF · RETOUR ANCIEN');assert.match(result.detail,/conforme.*50 s.*seuil 30 s/);
result=health(state,devices.map((d,i)=>({...d,returned_at:i?940:950})));assert.match(result.detail,/CL5 50 s.*QL1 1 min/);
