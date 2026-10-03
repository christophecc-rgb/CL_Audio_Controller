(() => {
  const el=id=>document.getElementById(id);
  const text=(tag,value)=>{const node=document.createElement(tag);node.textContent=value;return node;};
  let qrTimer;
  let backendRequired=false;
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
    await act(button.dataset.op,{password:el('password').value,duration:button.dataset.duration||'five_minutes'}); el('password').value='';
    if(button.dataset.op==='lock') el('qr').replaceChildren();
  });
  document.querySelectorAll('[data-mode]').forEach(button=>button.onclick=()=>act('mode',{mode:button.dataset.mode}));
  document.querySelectorAll('[data-arm]').forEach(button=>button.onclick=()=>act('arm',{armed:button.dataset.arm==='true'}));
  document.querySelectorAll('[data-qr]').forEach(button=>button.onclick=async()=>{
    const result=await act('qr',{role:button.dataset.qr,server_url:el('url').value}); if(!result) return;
    showQR('qr',result.svg);
    el('expiry').textContent='QR à usage unique — expire dans 2 minutes';
    clearTimeout(qrTimer); qrTimer=setTimeout(()=>{el('qr').replaceChildren();el('expiry').textContent='QR expiré';},120000);
  });
  el('configure-tls').onclick=async()=>{
    const result=await act('tls',{certificate:el('certificate').value,private_key:el('private-key').value,port:Number(el('tls-port').value),server_url:el('url').value});
    if(result) el('result').textContent='Configuration enregistrée. Utiliser Démarrer / recharger, puis le test iPhone.';
  };
  function showQR(id,svgText){
    const svg=new DOMParser().parseFromString(svgText,'image/svg+xml').documentElement;
    el(id).replaceChildren(document.importNode(svg,true));
  }
  el('server-choice').onchange=()=>{if(el('server-choice').value)el('url').value=el('server-choice').value;refresh().catch(()=>{});};
  el('first-setup').onclick=async()=>{
    try {
      await refresh();
      if(backendRequired){window.location.assign('http://127.0.0.1:5050/security/panel#first-setup');return;}
      el('onboarding').hidden=false;
    }catch(error){el('result').textContent=error.message;}
  };
  if(window.location.hash==='#first-setup')el('onboarding').hidden=false;
  el('prepare-https').onclick=async()=>{
    el('result').textContent='Création des certificats et démarrage HTTPS…';
    const result=await act('tls-setup',{server_url:el('url').value});
    if(result){el('onboarding').hidden=false;el('result').textContent='HTTPS prêt sur le Mac. Installer la confiance et effectuer le test iPhone.';}
  };
  el('start-https').onclick=()=>act('tls-start');
  el('enroll-phone').onclick=async()=>{
    const result=await act('tls-enroll');if(!result)return;
    showQR('trust-qr',result.svg);
    el('ca-download').href=result.enrollment.url;el('ca-download').hidden=false;
    el('ca-fingerprint').textContent='Empreinte SHA-256 de la CA : '+result.enrollment.fingerprint;
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
    const unlock=state.admin_unlock||{mode:state.unlocked?'five_minutes':'locked',remaining_seconds:300};
    const remaining=Number(unlock.remaining_seconds||0);
    el('admin-state').textContent=unlock.mode==='session'?'DÉVERROUILLÉ POUR CETTE SESSION':unlock.mode==='five_minutes'?`DÉVERROUILLÉ 5 MIN — ${Math.floor(remaining/60)}:${String(remaining%60).padStart(2,'0')} restantes`:'VERROUILLÉ';
    el('state').textContent=`${state.armed?'● ARMÉES':'○ DÉSARMÉES'} — ${state.mode==='show'?'MODE SPECTACLE':'MODE DÉVELOPPEMENT'} — admin ${state.unlocked?'déverrouillé':'verrouillé'}`;
    if(!state.unlocked) {el('qr').replaceChildren();el('expiry').textContent='';}
    el('pending').replaceChildren();
    (state.pending||[]).forEach(item=>{
      const row=text('article',`${item.name} · ${item.operator} · ${item.role} `);
      const choice=approvalChoices.get(item.id)||{type:item.role==='operator'?'permanent':'temporary',duration:43200};approvalChoices.set(item.id,choice);
      const type=document.createElement('select');type.setAttribute('aria-label','Type d’autorisation');
      [['temporary','Temporaire'],['permanent','Permanent']].forEach(([value,label])=>{const option=text('option',label);option.value=value;type.append(option);});type.value=choice.type;
      const duration=document.createElement('input');duration.type='number';duration.min='60';duration.max='86400';duration.step='1';duration.value=choice.duration;duration.setAttribute('aria-label','Durée temporaire en secondes');
      const detail=text('span','');
      function update(){duration.hidden=type.value==='permanent';detail.textContent=type.value==='permanent'?'Valide jusqu’à révocation':'Durée en secondes : 60 à 86400 (12 h = 43200)';}
      type.onchange=()=>{choice.type=type.value;update();};duration.oninput=()=>{choice.duration=duration.value;};update();
      const button=text('button','Approuver cet iPhone');button.onclick=async()=>{
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
      const row=text('article',`${item.name} · ${item.operator} · ${permanent&&item.role==='operator'?'iPhone autorisé — opérateur permanent':item.role+' · '+(permanent?'PERMANENT':'TEMPORAIRE')} · ${item.revoked?'révoqué':!item.active?'expiré':item.connected?'connecté':'autorisé, hors ligne'} · Dernière activité : ${activity} · ${expiry} `);
      row.style.borderLeft=permanent?'4px solid #8fc9ff':'4px solid #d9b85f';
      const revoke=text('button','Révoquer');revoke.onclick=()=>act('revoke',{device_id:item.id});row.append(revoke);
      const roles=document.createElement('select');['reader','operator','admin'].forEach(role=>{const option=text('option',role);option.value=role;roles.append(option);});roles.value=item.role;
      roles.onchange=()=>act('role',{device_id:item.id,role:roles.value});row.append(roles);el('devices').append(row);
    });
    const diag=await(await fetch('/security/diagnostics')).json();
    const https=diag.https||{};
    backendRequired=https.state==='BACKEND 5050 REQUIRED';
    if(!el('url').value)el('url').value=https.server_url||(https.network||{}).suggested_url||'';
    const network=https.network||{};
    const interfaces=network.interfaces||[];
    const usableIPv4=item=>/^(?:\d{1,3}\.){3}\d{1,3}$/.test(item.address)&&item.address.split('.').every(part=>Number(part)<=255)&&! /^(169\.254\.|127\.|0\.)/.test(item.address);
    const preferred=interfaces.find(item=>item.primary&&usableIPv4(item))||interfaces.find(usableIPv4)||interfaces.find(item=>item.primary)||interfaces[0];
    const candidates=[...(network.bonjour_name?[[network.bonjour_name,'Bonjour · '+network.bonjour_name]]:[]),...(network.interfaces||[]).map(item=>[item.address,item.name+' · '+item.address+(item.primary?' (principale)':'')])];
    const choicesKey=JSON.stringify(candidates)+https.port;
    if(el('server-choice').dataset.choices!==choicesKey){
      const previousChoice=el('server-choice').value;
      el('server-choice').replaceChildren(text('option','Choisir une interface'));el('server-choice').firstChild.value='';
      candidates.forEach(([host,label])=>{const option=text('option',label);option.value='https://'+host+':'+(https.port||8443);el('server-choice').append(option);});
      el('server-choice').dataset.choices=choicesKey;
      const preferredURL=preferred?'https://'+preferred.address+':'+(https.port||8443):'';
      el('server-choice').value=candidates.some(([host])=>'https://'+host+':'+(https.port||8443)===previousChoice)?previousChoice:preferredURL;
    }
    el('network-choice').textContent=backendRequired?'Configuration iPhone disponible sur le serveur HTTP 5050. Ouvrir Première configuration iPhone.':'Nom Bonjour : '+(network.bonjour_name||'non détecté')+' · Interface principale : '+(preferred?preferred.name+' — '+preferred.address:'non détectée')+' · Interfaces : '+(network.interfaces||[]).map(item=>item.name+' '+item.address+(item.primary?' (principale)':'')).join(', ');
    el('https-state').textContent=(https.ready?'HTTPS prêt sur le Mac':'HTTPS inactif / non vérifié')+' · '+(https.phone_verified?'iPhone vérifié':'test iPhone requis')+' · certificat '+(https.certificate_present?(https.certificate_valid?'valide':'non validé'):'absent')+' · nom '+(https.hostname_valid?'conforme':'non vérifié')+(https.error?' · '+https.error:'');
    const canConfigure=state.unlocked&&state.mode==='development';
    const authorized=(state.devices||[]).some(item=>item.active&&!item.revoked&&item.role==='operator'&&item.authorization_type==='permanent');
    el('connection-state').textContent=https.ready?'Connexion sécurisée prête':'Déverrouiller et préparer la connexion sécurisée.';
    el('phone-state').textContent=https.phone_verified?'iPhone vérifié':'En attente de confirmation sur l’iPhone.';
    el('device-state').textContent=authorized?'iPhone autorisé — opérateur permanent':(state.pending||[]).length?'Demande reçue : approuver cet iPhone ci-dessus.':'En attente d’ajout de la télécommande.';
    el('step-https').textContent=https.ready?'1. HTTPS prêt ✓':'1. HTTPS à préparer';
    el('step-phone').textContent=https.phone_verified?'2. iPhone vérifié ✓':'2. iPhone à vérifier';
    el('step-device').textContent=authorized?'3. Télécommande autorisée ✓':'3. Télécommande à autoriser';

    el('prepare-https').disabled=!canConfigure;el('start-https').disabled=!canConfigure;el('enroll-phone').disabled=!canConfigure||!https.ready;
    document.querySelectorAll('[data-qr]').forEach(button=>button.disabled=!canConfigure||!https.ready||!https.phone_verified||el('url').value.replace(/\/$/,'')!==https.server_url);
    if(https.ready&&https.server_url){
      const checkURL=https.server_url+'/remote/check';el('phone-check').href=checkURL;el('phone-check').textContent=checkURL;el('phone-check').hidden=false;
      if(el('check-qr').dataset.url!==checkURL){
        const response=await fetch('/security/check-qr');
        if(response.ok){const result=await response.json();showQR('check-qr',result.svg);el('check-qr').dataset.url=checkURL;}
      }
    }else{el('phone-check').hidden=true;el('check-qr').replaceChildren();el('check-qr').dataset.url='';}
    el('diagnostics').textContent=Object.entries(diag).map(([name,value])=>`${name.toUpperCase().padEnd(18)} ${value.link_state||value.state||'UNKNOWN'}`).join('\n');
  }
  refresh().catch(error=>el('result').textContent=error.message);
  setInterval(()=>refresh().catch(()=>{}),3000);
})();
