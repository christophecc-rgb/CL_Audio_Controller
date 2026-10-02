(() => {
  const el=id=>document.getElementById(id);
  const text=(tag,value)=>{const node=document.createElement(tag);node.textContent=value;return node;};
  let qrTimer;
  const approvalChoices=new Map();
  async function operation(op,data={}) {
    const response=await fetch('/security/admin/'+op,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    const result=await response.json(); if(!response.ok) throw new Error(result.error); return result;
  }
  async function act(op,data) {
    try { const result=await operation(op,data); el('result').textContent='✓ '+op; await refresh(); return result; }
    catch(error) {el('result').textContent=error.message; return null;}
  }
  document.querySelectorAll('[data-op]').forEach(button=>button.onclick=async()=>{
    if(button.dataset.op==='revoke'&&!confirm('Révoquer tous les appareils ?')) return;
    await act(button.dataset.op,{password:el('password').value}); el('password').value='';
    if(button.dataset.op==='lock') el('qr').replaceChildren();
  });
  document.querySelectorAll('[data-mode]').forEach(button=>button.onclick=()=>act('mode',{mode:button.dataset.mode}));
  document.querySelectorAll('[data-arm]').forEach(button=>button.onclick=()=>act('arm',{armed:button.dataset.arm==='true'}));
  document.querySelectorAll('[data-qr]').forEach(button=>button.onclick=async()=>{
    const result=await act('qr',{role:button.dataset.qr,server_url:el('url').value}); if(!result) return;
    const svg=new DOMParser().parseFromString(result.svg,'image/svg+xml').documentElement;
    el('qr').replaceChildren(document.importNode(svg,true));
    el('expiry').textContent='QR à usage unique — expire dans 2 minutes';
    clearTimeout(qrTimer); qrTimer=setTimeout(()=>{el('qr').replaceChildren();el('expiry').textContent='QR expiré';},120000);
  });
  el('configure-tls').onclick=async()=>{
    const result=await act('tls',{certificate:el('certificate').value,private_key:el('private-key').value,port:Number(el('tls-port').value),server_url:el('url').value});
    if(result) el('result').textContent='HTTPS enregistré. Redémarrer le backend puis vérifier le certificat depuis le téléphone.';
  };
  el('new-backup-secret').onclick=()=>{
    const hex=count=>Array.from(crypto.getRandomValues(new Uint8Array(count)),v=>v.toString(16).padStart(2,'0')).join('');
    el('backup-secret').value=hex(32);el('backup-session').value=hex(16);
    el('result').textContent='Nouveau secret préparé : le transférer localement au secours avant activation.';
  };
  async function backup(data){
    try{
      const response=await fetch('/api/scene-backup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
      const result=await response.json();if(!response.ok)throw new Error(result.error);
      el('backup-secret').value='';el('result').textContent=result.link_state;await refresh();
    }catch(error){el('result').textContent=error.message;}
  }
  el('configure-backup').onclick=()=>backup({enabled:true,show:el('backup-show').value,source_ip:el('backup-source').value,source_interface:el('backup-interface').value,destinations:[{host:el('backup-peer').value,enabled:true}],authentication:'hmac_v1',shared_secret:el('backup-secret').value,session:el('backup-session').value});
  el('disable-backup').onclick=()=>backup({enabled:false});
  async function refresh() {
    const response=await fetch('/security/status'); const state=await response.json();
    el('state').textContent=`${state.armed?'● ARMÉES':'○ DÉSARMÉES'} — ${state.mode==='show'?'MODE SPECTACLE':'MODE DÉVELOPPEMENT'} — admin ${state.unlocked?'déverrouillé':'verrouillé'}`;
    if(!state.unlocked) {el('qr').replaceChildren();el('expiry').textContent='';}
    el('pending').replaceChildren();
    (state.pending||[]).forEach(item=>{
      const row=text('article',`${item.name} · ${item.operator} · ${item.role} `);
      const choice=approvalChoices.get(item.id)||{type:'temporary',duration:43200};approvalChoices.set(item.id,choice);
      const type=document.createElement('select');type.setAttribute('aria-label','Type d’autorisation');
      [['temporary','Temporaire'],['permanent','Permanent']].forEach(([value,label])=>{const option=text('option',label);option.value=value;type.append(option);});type.value=choice.type;
      const duration=document.createElement('input');duration.type='number';duration.min='60';duration.max='86400';duration.step='1';duration.value=choice.duration;duration.setAttribute('aria-label','Durée temporaire en secondes');
      const detail=text('span','');
      function update(){duration.hidden=type.value==='permanent';detail.textContent=type.value==='permanent'?'Valide jusqu’à révocation':'Durée en secondes : 60 à 86400 (12 h = 43200)';}
      type.onchange=()=>{choice.type=type.value;update();};duration.oninput=()=>{choice.duration=duration.value;};update();
      const button=text('button','Autoriser');button.onclick=async()=>{
        const result=await act('approve',{request_id:item.id,authorization_type:type.value,lifetime:Number(duration.value)});
        if(result)approvalChoices.delete(item.id);
      };
      row.append(type,duration,detail,button);el('pending').append(row);
    });
    const pendingIDs=new Set((state.pending||[]).map(item=>item.id));
    for(const id of approvalChoices.keys())if(!pendingIDs.has(id))approvalChoices.delete(id);
    el('devices').replaceChildren();
    (state.devices||[]).forEach(item=>{
      const permanent=item.authorization_type==='permanent';
      const activity=item.last_seen==null?'aucune':new Date(item.last_seen*1000).toLocaleString();
      const expiry=permanent?'Valide jusqu’à révocation':`Expiration : ${item.expires==null?'inconnue':new Date(item.expires*1000).toLocaleString()}`;
      const row=text('article',`${item.name} · ${item.operator} · ${item.role} · ${permanent?'PERMANENT':'TEMPORAIRE'} · ${item.revoked?'révoqué':!item.active?'expiré':item.connected?'connecté':'autorisé, hors ligne'} · Dernière activité : ${activity} · ${expiry} `);
      row.style.borderLeft=permanent?'4px solid #8fc9ff':'4px solid #d9b85f';
      const revoke=text('button','Révoquer');revoke.onclick=()=>act('revoke',{device_id:item.id});row.append(revoke);
      const roles=document.createElement('select');['reader','operator','admin'].forEach(role=>{const option=text('option',role);option.value=role;roles.append(option);});roles.value=item.role;
      roles.onchange=()=>act('role',{device_id:item.id,role:roles.value});row.append(roles);el('devices').append(row);
    });
    const diag=await(await fetch('/security/diagnostics')).json();
    el('diagnostics').textContent=Object.entries(diag).map(([name,value])=>`${name.toUpperCase().padEnd(18)} ${value.link_state||value.state||'UNKNOWN'}`).join('\n');
  }
  refresh().catch(error=>el('result').textContent=error.message);
  setInterval(()=>refresh().catch(()=>{}),3000);
})();
