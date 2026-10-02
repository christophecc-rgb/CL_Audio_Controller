const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const {webcrypto, createHash, createHmac} = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const storageKey = 'cl-paired-device-v1';
function storage() {
  const values = new Map();
  return {getItem: key => values.get(key) || null, setItem: (key,value) => values.set(key,value), removeItem: key => values.delete(key)};
}
function environment() {
  const elements = {name:{value:'iPhone Christophe'},operator:{value:'Christophe'},remember:{checked:true},pair:{},status:{}};
  const ctx = {URL, URLSearchParams, Headers, Request, TextEncoder, crypto:webcrypto,
    sessionStorage:storage(),localStorage:storage(),
    location:{href:'https://server.local:8443/',origin:'https://server.local:8443',hash:'#code=one-use',pathname:'/remote/pair',hostname:'server.local',replace(url){this.replaced=url;}},
    history:{replaceState(){}},alert(message){ctx.alertMessage=message;},
    setTimeout, setInterval(){},document:{getElementById:id=>elements[id],addEventListener(){}}};
  ctx.window=ctx;
  return {ctx,elements};
}
async function paired(kind,remember,localFailure=false) {
  const {ctx,elements}=environment();elements.remember.checked=remember;
  if(localFailure)ctx.localStorage.setItem=()=>{throw new Error('Storage disabled');};
  const device={device_id:'device-1',token:'browser-secret-test-token',authorization_type:kind,role:'operator',expires:kind==='permanent'?null:123};
  ctx.fetch=async resource=>({ok:true,json:async()=>resource.endsWith('/request')?{request_id:'pending',claim:'claim-once'}:device});
  vm.runInNewContext(fs.readFileSync(path.join(root,'static/remote-pair.js'),'utf8'),ctx);
  await elements.pair.onclick();
  for(let i=0;i<10&&!ctx.location.replaced;i++)await new Promise(resolve=>setImmediate(resolve));
  assert.equal(ctx.location.replaced,'/');
  return {ctx,device};
}
test('explicit permanent consent stores credential persistently',async()=>{
  const {ctx,device}=await paired('permanent',true);
  assert.deepEqual(JSON.parse(ctx.localStorage.getItem(storageKey)),device);
  assert.equal(ctx.sessionStorage.getItem(storageKey),null);
});
test('permanent without consent stays in session storage',async()=>{
  const {ctx,device}=await paired('permanent',false);
  assert.deepEqual(JSON.parse(ctx.sessionStorage.getItem(storageKey)),device);
  assert.equal(ctx.localStorage.getItem(storageKey),null);
});
test('temporary never persists even if remember is selected',async()=>{
  const {ctx}=await paired('temporary',true);
  assert.equal(ctx.localStorage.getItem(storageKey),null);
  assert.equal(JSON.parse(ctx.sessionStorage.getItem(storageKey)).authorization_type,'temporary');
});
test('blocked persistent storage retains the claimed session and informs operator',async()=>{
  const {ctx}=await paired('permanent',true,true);
  assert.ok(ctx.sessionStorage.getItem(storageKey));assert.match(ctx.alertMessage,/nouvel appairage/);
});
test('a fresh browser session signs with permanent localStorage credentials',async()=>{
  const {ctx}=environment();
  const device={device_id:'persistent-device',token:'persistent-token',authorization_type:'permanent'};
  ctx.localStorage.setItem(storageKey,JSON.stringify(device));
  let observed;
  ctx.fetch=async(resource,options)=>{observed=options;return {status:200,ok:true};};
  vm.runInNewContext(fs.readFileSync(path.join(root,'static/remote-auth.js'),'utf8'),ctx);
  const body=JSON.stringify({action:'go',scene:31});
  await ctx.fetch('/action',{method:'POST',body});
  assert.equal(observed.headers.get('X-CL-Device'),device.device_id);
  const canonical=['POST','/action',observed.headers.get('X-CL-Timestamp'),observed.headers.get('X-CL-Nonce'),createHash('sha256').update(body).digest('hex')].join('\n');
  const expected=createHmac('sha256',createHash('sha256').update(device.token).digest()).update(canonical).digest('hex');
  assert.equal(observed.headers.get('X-CL-Signature'),expected);
  assert.equal(observed.headers.get('Authorization'),null);
});
test('a historical temporary credential in localStorage grants no automatic persistence',async()=>{
  const {ctx}=environment();ctx.localStorage.setItem(storageKey,JSON.stringify({device_id:'old',token:'old-token'}));
  let observed;ctx.fetch=async(resource,options)=>{observed=options;return {status:200,ok:true};};
  vm.runInNewContext(fs.readFileSync(path.join(root,'static/remote-auth.js'),'utf8'),ctx);
  await ctx.fetch('/action',{method:'POST',body:'{}'});
  assert.equal(observed.headers,undefined);
});
