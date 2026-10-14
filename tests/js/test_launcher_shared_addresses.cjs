const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync(require('path').resolve(__dirname,'../../launcher_control.py'),'utf8');
const nodes={};const el=id=>nodes[id]||(nodes[id]={textContent:'',getAttribute(k){return this[k]},setAttribute(k,v){this[k]=v},removeAttribute(k){delete this[k]}});
const copied=[],opened=[];
const ctx=vm.createContext({URL,el,bonjourShareURL:x=>x,navigator:{clipboard:{writeText:async x=>copied.push(x)}},window:{open:x=>opened.push(x)}});
vm.runInContext(source.slice(source.indexOf('function isShareableURL(value)'),source.indexOf('async function copyLtcValue')),ctx);
(async()=>{
for(const protocol of ['http','https']){
 const base=protocol+'://macchris.local:'+(protocol==='https'?8443:5050);
 ctx.state={lan_url:'http://127.0.0.1:5050/',shared_addresses:{remote_url:base+'/',showcue_url:base+'/show-info',local_certificate:protocol==='https'}};
 vm.runInContext('renderSharedAddresses(state)',ctx);
 assert.equal(el('remoteAddress').textContent,base+'/');
 assert.equal(new URL(el('sharedQR').src,'http://panel.local').searchParams.get('url'),base+'/');
 assert.equal(el('showqAddress').textContent,base+'/show-info');
 assert.equal(new URL(el('showcueQR').src,'http://panel.local').searchParams.get('url'),base+'/show-info');
 await vm.runInContext('copyAddress()',ctx);await vm.runInContext('copyShowQAddress()',ctx);
 vm.runInContext('openSharedRemote();openShowQ()',ctx);
 assert.deepEqual(copied.slice(-2),[base+'/',base+'/show-info']);
 assert.deepEqual(opened.slice(-2),copied.slice(-2));
 assert.equal(el('sharedProtocol').textContent,protocol==='https'?'🔒 HTTPS actif':'HTTP');
}
assert.match(el('sharedCertificate').textContent,/Certificat local/);
for(const host of ['localhost','127.0.0.1','192.168.1.5','10.8.0.1','169.254.3.4'])assert.equal(vm.runInContext(`isShareableURL('http://${host}:5050/')`,ctx),false);
assert.match(source,/onclick="openSharedRemote\(\)"/);
console.log('PASS shared HTTP/HTTPS display, copy and open');
})().catch(e=>{console.error(e);process.exitCode=1});
