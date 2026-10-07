const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('templates/show_info.html','utf8');
const fn=source.match(/async function api\(url,options=\{\}\)\{.*?return data\}/)[0];
const context={FormData:class{},fetch:null};vm.createContext(context);vm.runInContext(fn,context);
(async()=>{
 for(const [status,data,message] of [[403,{ok:false,error:'Appareil non autorisé pour le poste LUMIERE'},'Erreur 403 — Appareil non autorisé pour le poste LUMIERE'],[409,{ok:false,message:'La session active a changé'},'Erreur 409 — La session active a changé'],[400,{},'Erreur 400 — Requête refusée sans explication']]){
  context.fetch=async()=>({status,ok:false,json:async()=>data});
  await assert.rejects(context.api('/test'),e=>e.message===message);
 }
 context.fetch=async()=>({status:500,ok:false,json:async()=>{throw new SyntaxError('HTML')}});
 await assert.rejects(context.api('/test'),e=>e.message==='Erreur 500 — Réponse serveur non JSON');
 console.log('ShowCue API error propagation: passed');
})().catch(e=>{console.error(e);process.exitCode=1});
