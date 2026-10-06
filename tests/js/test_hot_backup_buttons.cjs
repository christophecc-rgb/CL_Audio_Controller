const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync(require('path').resolve(__dirname,'../../launcher_control.py'),'utf8');
const a=source.indexOf('    const backupStatus = document.getElementById("cl-backup-status")');
const b=source.indexOf('    function placeMTCBridgeBesideRemoteAccess()',a);
const nodes=new Map();
function el(id){if(!nodes.has(id))nodes.set(id,{value:'',checked:false,disabled:false,textContent:'',addEventListener(){}});return nodes.get(id)}
let current={mode:'mtc',host:'',state:'DISABLED'},calls=[];
const ctx=vm.createContext({document:{getElementById:el},setInterval(){},fetch:async(url,options)=>{
 if(options){const body=JSON.parse(options.body);calls.push(body);current={...current,...body};}
 return {ok:true,json:async()=>current};
}});
vm.runInContext(source.slice(a,b),ctx);
(async()=>{
 el('cl-backup-host').value='192.168.1.138';el('cl-backup-ext').checked=true;el('cl-backup-set').checked=true;
 await el('cl-backup-apply').onclick.call(el('cl-backup-apply'));
 assert.deepEqual(calls[0],{mode:'hot_backup',host:'192.168.1.138',ext_off:true,same_set:true});
 assert.equal(el('cl-backup-disable').disabled,false);
 await el('cl-backup-disable').onclick.call(el('cl-backup-disable'));
 assert.deepEqual(calls[1],{mode:'mtc'});
 assert.equal(el('cl-backup-disable').disabled,true);
 assert.equal(el('cl-backup-host').value,'192.168.1.138');
  vm.runInContext("var abletonReaders=[{host:'MacBook-Pro.local',addresses:['192.168.1.138']}];",ctx);
 el('cl-backup-host').value='MacBook-Pro.local';
 await el('cl-backup-apply').onclick.call(el('cl-backup-apply'));
 assert.equal(calls[2].host,'192.168.1.138');
 el('cl-backup-host').value='Absent.local';
 await el('cl-backup-apply').onclick.call(el('cl-backup-apply'));
 assert.equal(calls.length,3);
 assert.match(el('cl-backup-status').textContent,/Bonjour non résolu/);
 console.log('PASS: enable/disable, Bonjour resolution, unresolved-name refusal and address retained.');
})().catch(e=>{console.error(e);process.exitCode=1});
