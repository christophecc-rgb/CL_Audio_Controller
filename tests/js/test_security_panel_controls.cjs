// Execute the real security panel against a local in-memory DOM/API fixture.
const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert/strict');
const root=path.resolve(__dirname,'../..');
const html=fs.readFileSync(path.join(root,'static/security-panel.html'),'utf8');
class Element {
 constructor(tag='div'){this.tagName=tag;this.children=[];this.dataset={};this.style={};this.attrs={};this.textContent='';this.value='';this.hidden=false;this.disabled=false;}
 append(...items){this.children.push(...items);}
 replaceChildren(...items){this.children=items;}
 setAttribute(k,v){this.attrs[k]=v;}
 getAttribute(k){return this.attrs[k];}
 contains(){return false;}
 focus(){}
 get firstChild(){return this.children[0];}
}
const nodes=Object.fromEntries([...html.matchAll(/id="([^"]+)"/g)].map(m=>[m[1],new Element()]));
for(const [id,node] of Object.entries(nodes))node.id=id;
const buttons=[...html.matchAll(/<button([^>]*)>/g)].map(m=>{
 const id=m[1].match(/id="([^"]+)"/);const button=id?nodes[id[1]]:new Element('button');
 for(const data of m[1].matchAll(/data-([a-z]+)="([^"]+)"/g))button.dataset[data[1]]=data[2];
 return button;
});
const descendants=node=>node.children.flatMap(child=>[child,...descendants(child)]);
const state={unlocked:true,mode:'development',armed:false,admin_unlock:{mode:'session'},devices:[],pending:[]};
const calls=[],timers=new Map();let timerId=0,poll;
const flush=()=>new Promise(resolve=>setImmediate(resolve));
const context={document:{getElementById:id=>nodes[id],createElement:tag=>new Element(tag),querySelectorAll:selector=>buttons.filter(b=>Object.hasOwn(b.dataset,selector.slice(6,-1)))},
 window:{location:{hash:''}},setInterval:fn=>{poll=fn;},setTimeout:fn=>{timers.set(++timerId,fn);return timerId;},clearTimeout:id=>timers.delete(id),
 fetch:async(url,options)=>{
  if(options){const payload=JSON.parse(options.body);calls.push({url,payload});
   if(url.endsWith('/arm'))state.armed=payload.armed;
   if(url.endsWith('/mode')){state.mode=payload.mode;if(state.mode==='show'){state.armed=true;state.unlocked=false;state.admin_unlock={mode:'locked'};}}
   if(url.endsWith('/role'))state.devices[0].role=payload.role;
   if(url.endsWith('/unlock'))state.admin_unlock={mode:payload.duration};
   if(url.endsWith('/lock')){state.unlocked=false;state.admin_unlock={mode:'locked'};}
   if(url.endsWith('/approve'))state.pending=[];
   return {ok:true,json:async()=>({ok:true})};
  }
  return {ok:true,json:async()=>url==='/security/status'?state:{https:{ready:false,network:{}}}};
 }};
vm.runInNewContext(fs.readFileSync(path.join(root,'static/security-panel.js'),'utf8'),context);
(async()=>{
 await flush();
 assert.equal((html.match(/id="arm-toggle"/g)||[]).length,1);assert.doesNotMatch(html,/data-arm=/);
 assert.equal(nodes['arm-toggle'].textContent,'Armer les télécommandes');
 await nodes['arm-toggle'].onclick();
 assert.equal(calls.at(-1).payload.armed,true);assert.equal(nodes['arm-toggle'].textContent,'Désarmer les télécommandes');
 assert.match(nodes.state.textContent,/Télécommandes armées/);assert.equal(nodes.result.textContent,'');
 await nodes['arm-toggle'].onclick();assert.equal(calls.at(-1).payload.armed,false);
 assert.equal(nodes['arm-toggle'].textContent,'Armer les télécommandes');
 state.devices=[{id:'phone',name:'iPhone',operator:'Chris',role:'operator',active:true,authorization_type:'permanent',permissions:{go:true}}];await poll();await flush();
 assert.ok(descendants(nodes.devices).some(n=>n.textContent==='○ Commandes désarmées'));
 const role=descendants(nodes.devices).find(n=>n.attrs['aria-label']==='Rôle de iPhone');
 assert.deepEqual(role.children.map(n=>n.textContent),['Administrateur','Opérateur / Télécommande','ShowQ uniquement']);
 role.value='reader';await role.onchange();
 assert.ok(descendants(nodes.devices).some(n=>n.textContent==='Lecture ShowQ · indépendante de l’armement'));
 assert.ok(!descendants(nodes.devices).some(n=>n.textContent==='Enregistrer les droits'));
 // Re-render does not resurrect old feedback or add per-button feedback nodes.
 const message=nodes.result.textContent;await poll();await flush();assert.equal(nodes.result.textContent,message);
 for(const callback of [...timers.values()])callback();assert.equal(nodes.result.textContent,'');
 assert.doesNotMatch(fs.readFileSync(path.join(root,'static/security-panel.js'),'utf8'),/feedbacks\.get|button\.after|Armement mis à jour\./);
 state.pending=[{id:'pending',name:'new phone',role:'operator'}];await poll();await flush();
 const pending=descendants(nodes.pending);const pendingRole=pending.find(n=>n.attrs['aria-label']==='Rôle à attribuer à new phone');
 pendingRole.value='reader';pendingRole.onchange();await pending.find(n=>n.textContent==='Approuver').onclick();
 assert.equal(calls.at(-1).payload.role,'reader');assert.equal(calls.at(-1).payload.authorization_type,'permanent');
 await nodes['development-toggle'].onclick();assert.equal(nodes['development-state'].textContent,'● Développement persistant actif');
 await nodes['development-toggle'].onclick();assert.equal(calls.at(-1).url,'/security/admin/lock');
 state.unlocked=true;state.mode='development';state.admin_unlock={mode:'session'};await poll();await flush();
 await nodes['show-mode'].onclick();assert.equal(calls.at(-1).payload.mode,'show');assert.equal(nodes['show-mode-state'].textContent,'Mode spectacle actif');
 assert.equal(nodes['arm-toggle'].disabled,true);assert.match(nodes.state.textContent,/armées/);
 console.log('PASS security panel single toggle, role selection, reader state, show mode, development state and transient feedback');
})().catch(error=>{console.error(error);process.exitCode=1});
