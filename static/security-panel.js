(() => {
  const el=id=>document.getElementById(id);
  const text=(tag,value)=>{const node=document.createElement(tag);node.textContent=value;return node;};
  let qrTimer;
  let showcueURL='';
  let setupInitialized=false;
  let pendingKey='';
  let devicesKey='';
  let setupCompleted=false;
  const feedbacks=new Map();
  function feedback(button,message,error=false){
    if(!button){el('result').textContent=message;return;}
    const key=button.dataset.feedbackKey||button.id||button.dataset.op+':'+(button.dataset.duration||'')||'action';
    feedbacks.set(key,{message,error});
    let node=button.nextElementSibling;
    if(!node||!node.classList.contains('feedback')){node=text('p','');node.className='feedback';node.setAttribute('role','status');button.after(node);}
    node.textContent=message;node.classList.toggle('error',error);
  }
  const messages={setup:'Mot de passe créé.',unlock:'Administration déverrouillée.',lock:'Administration verrouillée.',mode:'Mode mis à jour.',arm:'Armement mis à jour.',approve:'Appareil approuvé.',revoke:'Autorisation révoquée.',role:'Rôle mis à jour.',qr:'QR prêt.',password:'Mot de passe changé.','tls-start':'HTTPS rechargé.','tls-setup':'HTTPS prêt. Installer la confiance et effectuer le test iPhone.','tls-enroll':'Certificat public prêt.',tls:'Configuration enregistrée. Recharger HTTPS, puis tester l’iPhone.'};
  let backendRequired=false;
  const approvalChoices=new Map();
  async function operation(op,data={}) {
    const response=await fetch('/security/admin/'+op,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    const result=await response.json(); if(!response.ok) throw new Error(result.error); return result;
  }
  async function act(op,data,button) {
    try { const result=await operation(op,data); feedback(button,messages[op]||'Opération terminée.'); await refresh(); if(button&&button.dataset.feedbackKey){const current=document.querySelector('[data-feedback-key="'+CSS.escape(button.dataset.feedbackKey)+'"]');if(current)feedback(current,messages[op]||'Opération terminée.');} return result; }
    catch(error) {feedback(button,error.message,true); return null;}
  }
  document.querySelectorAll('[data-op]').forEach(button=>button.onclick=async()=>{
    if(button.dataset.op==='revoke'&&!confirm('Révoquer tous les appareils ?')) return;
    await act(button.dataset.op,{password:el('password').value,duration:button.dataset.duration||'five_minutes'},button); el('password').value='';
    if(button.dataset.op==='lock') el('qr').replaceChildren();
  });
  document.querySelectorAll('[data-mode]').forEach(button=>button.onclick=()=>act('mode',{mode:button.dataset.mode},button));
  document.querySelectorAll('[data-arm]').forEach(button=>button.onclick=()=>act('arm',{armed:button.dataset.arm==='true'},button));
  document.querySelectorAll('[data-qr]').forEach(button=>button.onclick=async()=>{
    const result=await act('qr',{role:button.dataset.qr,server_url:el('url').value},button); if(!result) return;
    showQR('qr',result.svg);
    el('expiry').textContent='QR à usage unique — expire dans 2 minutes';
    clearTimeout(qrTimer); qrTimer=setTimeout(()=>{el('qr').replaceChildren();el('expiry').textContent='QR expiré';},120000);
  });
  el('open-showcue').onclick=async()=>{
    try{
      const response=await fetch('/security/showcue-qr');
      const result=await response.json();if(!response.ok)throw new Error(result.error);
      showcueURL=result.url;showQR('showcue-qr',result.svg);
      el('showcue-link').href=showcueURL;el('showcue-link').textContent=showcueURL;
      el('showcue-access').hidden=false;feedback(el('open-showcue'),'Scanner le QR pour ouvrir ShowCue.');
      el('close-showcue').focus();
    }catch(error){feedback(el('open-showcue'),error.message,true);}
  };
  function closeShowCue(){feedback(el('open-showcue'),'');el('showcue-access').hidden=true;el('showcue-qr').replaceChildren();el('open-showcue').focus();}
  el('close-showcue').onclick=closeShowCue;
  el('showcue-access').onkeydown=event=>{if(event.key==='Escape')closeShowCue();};
  el('copy-showcue').onclick=async()=>{
    try{await navigator.clipboard.writeText(showcueURL);feedback(el('copy-showcue'),'Adresse copiée.');}
    catch(error){feedback(el('copy-showcue'),'Copie indisponible. Sélectionner le lien pour copier l’adresse.',true);}
  };
  el('configure-tls').onclick=async()=>{
    const result=await act('tls',{certificate:el('certificate').value,private_key:el('private-key').value,port:Number(el('tls-port').value),server_url:el('url').value},el('configure-tls'));
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
      el('setup-details').open=true;
    }catch(error){el('result').textContent=error.message;}
  };
  if(window.location.hash==='#first-setup')el('setup-details').open=true;
  el('prepare-https').onclick=async()=>{
    feedback(el('prepare-https'),'Création des certificats et démarrage HTTPS…');
    const result=await act('tls-setup',{server_url:el('url').value},el('prepare-https'));
    if(result){el('setup-details').open=true;feedback(el('prepare-https'),messages['tls-setup']);}
  };
  el('start-https').onclick=()=>act('tls-start',{},el('start-https'));
  el('enroll-phone').onclick=async()=>{
    const result=await act('tls-enroll',{},el('enroll-phone'));if(!result)return;
    showQR('trust-qr',result.svg);
    el('ca-download').href=result.enrollment.url;el('ca-download').hidden=false;
    el('ca-fingerprint').textContent='Empreinte SHA-256 de la CA : '+result.enrollment.fingerprint;
  };
  el('new-backup-secret').onclick=()=>{
    const hex=count=>Array.from(crypto.getRandomValues(new Uint8Array(count)),v=>v.toString(16).padStart(2,'0')).join('');
    el('backup-secret').value=hex(32);el('backup-session').value=hex(16);
    feedback(el('new-backup-secret'),'Secret préparé : le transférer localement au secours avant activation.');
  };
  async function backup(data,button){
    try{
      const response=await fetch('/api/scene-backup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
      const result=await response.json();if(!response.ok)throw new Error(result.error);
      el('backup-secret').value='';feedback(button,result.link_state);await refresh();
    }catch(error){feedback(button,error.message,true);}
  }
  el('configure-backup').onclick=()=>backup({enabled:true,show:el('backup-show').value,source_ip:el('backup-source').value,source_interface:el('backup-interface').value,destinations:[{host:el('backup-peer').value,enabled:true}],authentication:'hmac_v1',shared_secret:el('backup-secret').value,session:el('backup-session').value},el('configure-backup'));
  el('disable-backup').onclick=()=>backup({enabled:false},el('disable-backup'));
  async function refresh() {
    const response=await fetch('/security/status'); const state=await response.json();
    const unlock=state.admin_unlock||{mode:state.unlocked?'five_minutes':'locked',remaining_seconds:300};
    const remaining=Number(unlock.remaining_seconds||0);
    el('admin-state').textContent=unlock.mode==='development'?'DÉVELOPPEMENT PERSISTANT SUR CE MAC':unlock.mode==='session'?'DÉVERROUILLÉ POUR CETTE SESSION':unlock.mode==='five_minutes'?`DÉVERROUILLÉ 5 MIN — ${Math.floor(remaining/60)}:${String(remaining%60).padStart(2,'0')} restantes`:'VERROUILLÉ';
    el('state').textContent=state.armed?'● Armées':'○ Désarmées';
    el('top-mode').textContent=state.mode==='show'?'Spectacle':'Configuration';
    el('top-admin').textContent=state.unlocked?(unlock.mode==='development'?'Développement persistant':'Déverrouillée'):'Verrouillée';
    if(!state.unlocked) {el('qr').replaceChildren();el('expiry').textContent='';}
    const nextPendingKey=JSON.stringify(state.pending||[]);
    if(nextPendingKey!==pendingKey&&!el('pending').contains(document.activeElement)){
    pendingKey=nextPendingKey;
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
        const result=await act('approve',{request_id:item.id,authorization_type:type.value,lifetime:Number(duration.value)},button);
        if(result)feedback(el('pending'),messages.approve);
        if(result)approvalChoices.delete(item.id);
      };
      row.append(type,duration,detail,button);el('pending').append(row);
    });
    }
    const pendingIDs=new Set((state.pending||[]).map(item=>item.id));
    for(const id of approvalChoices.keys())if(!pendingIDs.has(id))approvalChoices.delete(id);
    const nextDevicesKey=JSON.stringify(state.devices||[]);
    if(nextDevicesKey!==devicesKey&&!el('devices').contains(document.activeElement)){
    devicesKey=nextDevicesKey;
    el('devices').replaceChildren();
    (state.devices||[]).forEach(item=>{
      const permanent=item.authorization_type==='permanent';
      const activity=item.last_seen==null?'aucune':new Date(item.last_seen*1000).toLocaleString();
      const expiry=permanent?'Valide jusqu’à révocation':`Expiration : ${item.expires==null?'inconnue':new Date(item.expires*1000).toLocaleString()}`;
      const row=document.createElement('article');
      row.append(text('h3',item.name+' · '+item.operator));
      row.append(text('p','Autorisation : '+(item.revoked?'révoquée':!item.active?'expirée':permanent?'permanente · jusqu’à révocation':'temporaire · '+expiry)));
      row.append(text('p','Connexion actuelle : '+(item.connected?'connecté':'hors ligne')+' · Rôle : '+item.role));
      const meta=text('p','Dernière activité : '+activity);meta.className='device-meta';row.append(meta);
      row.style.borderLeft=permanent?'4px solid #8fc9ff':'4px solid #d9b85f';
      const revoke=text('button','Révoquer');revoke.dataset.feedbackKey=item.id+':revoke';revoke.onclick=()=>act('revoke',{device_id:item.id},revoke);row.append(revoke);
      const roles=document.createElement('select');['reader','operator','admin'].forEach(role=>{const option=text('option',role);option.value=role;roles.append(option);});roles.value=item.role;
      roles.setAttribute('aria-label','Rôle de '+item.name);roles.dataset.feedbackKey=item.id+':role';
      roles.onchange=()=>act('role',{device_id:item.id,role:roles.value},roles);row.append(roles);el('devices').append(row);
      for(const control of [revoke,roles]){const saved=feedbacks.get(control.dataset.feedbackKey);if(saved)feedback(control,saved.message,saved.error);}
    });
    }
    el('device-count').textContent='('+ (state.devices||[]).length +')';
    if(!(state.devices||[]).length&&!el('devices').children.length)el('devices').append(text('p','Aucun appareil autorisé. Ouvrir la configuration iPhone pour en ajouter un.'));
    const diag=await(await fetch('/security/diagnostics')).json();
    const https=diag.https||{};
    backendRequired=https.state==='BACKEND 5050 REQUIRED'||(diag.http||{}).port===5055;
    el('page-title').textContent=backendRequired?'Maintenance locale':'Télécommandes CL';
    el('service-context').textContent=backendRequired?'Lanceur · 5055 — Configuration des télécommandes sur le serveur 5050':'Télécommandes · Serveur 5050 — Maintenance locale sur le lanceur 5055';
    el('open-showcue').disabled=backendRequired||!https.ready;
    if(el('showcue-access').hidden===false&&(!https.ready||showcueURL!==String(https.server_url||'').replace(/\/$/,'')+'/show-info')){el('showcue-access').hidden=true;el('showcue-qr').replaceChildren();}
    el('top-https').textContent=backendRequired?'Voir serveur 5050':https.ready?'HTTPS prêt':'HTTPS inactif';
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
    el('https-state').textContent=(https.ready?'HTTPS prêt sur le Mac':'HTTPS inactif / non vérifié')+' · '+(https.phone_verified?'iPhone vérifié':'test ponctuel non confirmé / expiré')+' · certificat '+(https.certificate_present?(https.certificate_valid?'valide':'non validé'):'absent')+' · nom '+(https.hostname_valid?'conforme':'non vérifié')+(https.error?' · '+https.error:'');
    const canConfigure=state.unlocked&&state.mode==='development';
    const authorized=(state.devices||[]).some(item=>item.active&&!item.revoked&&item.role==='operator'&&item.authorization_type==='permanent');
    el('connection-state').textContent=https.ready?'Connexion sécurisée prête':'Déverrouiller et préparer la connexion sécurisée.';
    el('phone-state').textContent=https.phone_verified?'Test ponctuel confirmé.':'Test ponctuel non confirmé ou expiré. Les autorisations existantes restent valides.';
    el('device-state').textContent=authorized?'iPhone autorisé — opérateur permanent':(state.pending||[]).length?'Demande reçue : approuver cet iPhone ci-dessus.':'En attente d’ajout de la télécommande.';
    el('step-https').textContent=https.ready?'1. HTTPS prêt ✓':'1. HTTPS à préparer';
    el('step-phone').textContent=https.phone_verified?'2. Test ponctuel confirmé ✓':'2. Test ponctuel à effectuer';
    el('step-device').textContent=authorized?'3. Télécommande autorisée ✓':'3. Télécommande à autoriser';

    const complete=https.ready&&authorized;
    el('setup-status').textContent=complete?'· Terminée':'· Ajouter un appareil';
    if(!setupInitialized){el('setup-details').open=!complete&&!backendRequired||window.location.hash==='#first-setup';setupInitialized=true;}
    else if(complete&&!setupCompleted)el('setup-details').open=false;
    setupCompleted=complete;
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
