const fs=require('fs'),vm=require('vm'),assert=require('assert'),{webcrypto}=require('crypto');
const source=fs.readFileSync('static/remote-auth.js','utf8');
const id='0123456789abcdef0123456789abcdef';
function fixture({paired=true,temporary=false,origin='https://show.local:8443',response={ok:true,status:200}}={}){
 const raw=JSON.stringify({device_id:id,token:'NEVER-PRINT-THIS-TOKEN',authorization_type:temporary?'temporary':'permanent'});
 const storage={getItem:()=>paired?raw:null};const calls=[];
 const context={URL,Headers,Request,TextEncoder,crypto:webcrypto,location:{origin,href:origin+'/show-info'},sessionStorage:temporary?storage:{getItem:()=>null},localStorage:temporary?{getItem:()=>null}:storage,document:{addEventListener(){},getElementById(){return null}},window:{fetch:async(resource,options)=>{calls.push({resource,options});return response;}}};
 vm.createContext(context);vm.runInContext(source,context);return {context,calls};
}
(async()=>{
 for(const path of ['/show-info/cues/cue_test','/show-info/cues/cue_test/notes/FOH']){
  const {context,calls}=fixture();await context.window.fetch(path,{method:'PUT',body:'{"session_id":"test","text":"note"}',headers:{'Content-Type':'application/json'}});
  assert.equal(calls.length,1);const headers=calls[0].options.headers;
  for(const name of ['X-CL-Device','X-CL-Timestamp','X-CL-Nonce','X-CL-Signature'])assert(headers.has(name));
  assert.equal(headers.get('X-CL-Device'),id);assert.equal(headers.get('Content-Type'),'application/json');
  const diagnostic=context.window.CLRemoteAuthDiagnostic;assert.equal(diagnostic.origin,'https://show.local:8443');assert.equal(diagnostic.request.device_id,id);assert(diagnostic.pairing_found);
  assert(!JSON.stringify(diagnostic).includes('NEVER-PRINT-THIS-TOKEN'));assert(!JSON.stringify(diagnostic).includes(headers.get('X-CL-Signature')));
 }
 const absent=fixture({paired:false});await absent.context.window.fetch('/show-info/cues/test',{method:'PUT',body:'{}'});
 assert.equal(absent.context.window.CLRemoteAuthDiagnostic.pairing_found,false);assert.equal(absent.context.window.CLRemoteAuthDiagnostic.request.headers['X-CL-Device'],false);
 const different=fixture();await different.context.window.fetch('https://192.168.1.5:8443/show-info/cues/test',{method:'PUT',body:'{}'});
 assert(!different.calls[0].options.headers);assert.equal(different.context.window.CLRemoteAuthDiagnostic.request.headers['X-CL-Signature'],false);
 const temp=fixture({temporary:true});await temp.context.window.fetch('/show-info/cues/test',{method:'PUT',body:'{}'});assert.equal(temp.context.window.CLRemoteAuthDiagnostic.storage_source,'sessionStorage');
 console.log('ShowCue signed PUT, notes, missing pairing, origin separation and secret-free diagnostics: passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
