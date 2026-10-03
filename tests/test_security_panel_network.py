"""Execute the actual panel script against its HTML IDs and diagnostics schema."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_network_binding_and_launcher_handoff():
    ids = re.findall(r'id="([^"]+)"', (ROOT / 'static/security-panel.html').read_text())
    harness = r'''
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
async function render(network,launcher=false){
  class Element {
    constructor(){this.value='';this.dataset={};this.children=[];this.textContent='';this.style={};}
    replaceChildren(...nodes){this.children=nodes;}
    setAttribute(){}
    contains(node){return this.children.includes(node);}
    append(...nodes){this.children.push(...nodes);}
    get firstChild(){return this.children[0];}
  }
  const nodes=Object.fromEntries(IDS.map(id=>[id,new Element()]));
  const state={mode:'development',unlocked:true,pending:[],devices:[]};
  const qr=new Element();qr.dataset.qr='operator';
  let destination, poll, verified=false, ready=false;
  const context={document:{getElementById:id=>nodes[id],createElement:()=>new Element(),querySelectorAll:selector=>selector==='[data-qr]'?[qr]:[]},
    window:{location:{hash:'',assign:url=>destination=url}},setInterval:callback=>{poll=callback;},setTimeout:()=>{},clearTimeout:()=>{},
    fetch:async url=>({ok:true,json:async()=>url==='/security/status'?state: {https:launcher?{state:'BACKEND 5050 REQUIRED'}:{port:8443,network,phone_verified:verified,ready,server_url:network.suggested_url}}})};
  vm.runInNewContext(fs.readFileSync(SOURCE,'utf8'),context);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(nodes.result.textContent,'');
  return {nodes,qr,update:async patch=>{Object.assign(state,patch);await poll();await new Promise(resolve=>setImmediate(resolve));},ready:async()=>{ready=true;nodes['check-qr'].dataset.url=network.suggested_url+'/remote/check';await poll();await new Promise(resolve=>setImmediate(resolve));},confirm:async()=>{verified=true;await poll();await new Promise(resolve=>setImmediate(resolve));},click:async()=>{await nodes['first-setup'].onclick();return destination;}};
}
(async()=>{
 const network={bonjour_name:'MacChris.local',suggested_url:'https://MacChris.local:8443',interfaces:[
  {name:'en12',address:'169.254.142.16',primary:false},
  {name:'en8',address:'172.20.10.3',primary:true}]};
 const panel=await render(network);
 const {nodes}=panel;
 assert.match(nodes['network-choice'].textContent,/Nom Bonjour : MacChris.local/);
 assert.match(nodes['network-choice'].textContent,/Interface principale : en8 — 172.20.10.3/);
 assert.equal(nodes['server-choice'].value,'https://172.20.10.3:8443');
 assert.equal(nodes.url.value,network.suggested_url);
 assert.match(nodes['https-state'].textContent,/test ponctuel non confirmé/);
 assert.equal(panel.qr.disabled,true);
 await panel.ready();
 assert.equal(panel.qr.disabled,true);
 assert.match(nodes['step-https'].textContent,/HTTPS prêt/);
 await panel.confirm();
 assert.match(nodes['https-state'].textContent,/iPhone vérifié/);
 assert.equal(panel.qr.disabled,false);
 assert.match(nodes['step-phone'].textContent,/Test ponctuel confirmé/);
 await panel.update({pending:[{id:'pending1',name:'iPhone',operator:'Chris',role:'operator'}]});
 assert.equal(nodes.pending.children.length,1);
 assert.match(nodes['device-state'].textContent,/Demande reçue/);
 assert.equal(nodes.pending.children[0].children[0].value,'permanent');
 await panel.update({pending:[],devices:[{id:'device1',name:'iPhone',operator:'Chris',role:'operator',authorization_type:'permanent',active:true,revoked:false}]});
 assert.equal(nodes.devices.children.length,1);
 assert.match(nodes['device-state'].textContent,/iPhone autorisé — opérateur permanent/);
 assert.match(nodes['step-device'].textContent,/Télécommande autorisée/);
 await panel.update({unlocked:false});
 assert.equal(panel.qr.disabled,true);
 assert.equal(nodes['admin-state'].textContent,'VERROUILLÉ');
 const fallback=await render({...network,interfaces:network.interfaces.map(item=>({...item,primary:false}))});
 assert.equal(fallback.nodes['server-choice'].value,'https://172.20.10.3:8443');
 nodes['server-choice'].value='https://MacChris.local:8443';
 await nodes['server-choice'].onchange();
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(nodes.url.value,'https://MacChris.local:8443');
 assert.equal(nodes['server-choice'].value,'https://MacChris.local:8443');
 const launcher=await render({},true);
 assert.match(launcher.nodes['network-choice'].textContent,/5050/);
 assert.doesNotMatch(launcher.nodes['network-choice'].textContent,/non détecté/);
 assert.equal(await launcher.click(),'http://127.0.0.1:5050/security/panel#first-setup');
})();
'''
    subprocess.run(['node', '-e', 'const IDS='+json.dumps(ids)+';const SOURCE='+json.dumps(str(ROOT/'static/security-panel.js'))+';'+harness], check=True, capture_output=True, text=True)
