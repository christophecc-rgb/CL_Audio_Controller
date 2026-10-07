/* Pairing absorbs credentials; existing command handlers keep their payloads. */
(() => {
  const original = window.fetch.bind(window);
  const bytes = value => new TextEncoder().encode(value);
  const hex = array => Array.from(new Uint8Array(array), n => n.toString(16).padStart(2, '0')).join('');
  const storageKey = 'cl-paired-device-v1';
  function credential() {
    try {
      const temporary=sessionStorage.getItem(storageKey);
      if (temporary) return temporary;
      const persistent=localStorage.getItem(storageKey);
      if (persistent && JSON.parse(persistent).authorization_type==='permanent') return persistent;
    } catch (_) { /* Storage unavailable or malformed: no anonymous command bypass. */ }
    return null;
  }
  const headerNames=['X-CL-Device','X-CL-Timestamp','X-CL-Nonce','X-CL-Signature'];
  function diagnostic(){
    const result={version:'identity-diagnostics-1',origin:location.origin,pairing_found:false,device_id:null,storage_source:null,storage_available:true};
    try{
      const temporary=sessionStorage.getItem(storageKey),persistent=localStorage.getItem(storageKey);
      const id=value=>/^[a-f0-9]{32}$/.test(value||'')?value:null;
      result.session_device_id=temporary?id(JSON.parse(temporary).device_id):null;
      result.persistent_device_id=persistent?id(JSON.parse(persistent).device_id):null;
      const raw=credential();
      if(raw){const value=JSON.parse(raw);result.device_id=id(value.device_id);result.pairing_found=Boolean(result.device_id);result.storage_source=temporary?'sessionStorage':'localStorage';}
    }catch(_){result.storage_available=false;}
    return result;
  }
  window.CLRemoteAuthDiagnostic=diagnostic();
  function refreshDiagnostic(){
    const node=document.getElementById('cl-remote-auth-diagnostic');
    if(node)node.textContent=JSON.stringify(window.CLRemoteAuthDiagnostic,null,2);
  }
  window.fetch = async (resource, options = {}) => {
    const url = new URL(typeof resource === 'string' ? resource : resource.url, location.href);
    const method = (options.method || (resource instanceof Request ? resource.method : 'GET')).toUpperCase();
    const stored = credential();
    if (stored && url.origin === location.origin && !['GET', 'HEAD', 'OPTIONS'].includes(method) && !url.pathname.startsWith('/security/') && !url.pathname.startsWith('/remote/pair/')) {
      if (!crypto.subtle) throw new Error('Télécommande : HTTPS requis');
      const device = JSON.parse(stored);
      const body = typeof options.body === 'string' ? options.body : '';
      if (options.body && typeof options.body !== 'string') throw new Error('Cette opération doit être effectuée depuis le serveur local');
      const timestamp = String(Date.now() / 1000);
      const nonce = hex(crypto.getRandomValues(new Uint8Array(16)));
      const bodyHash = hex(await crypto.subtle.digest('SHA-256', bytes(body)));
      const keyHash = await crypto.subtle.digest('SHA-256', bytes(device.token));
      const key = await crypto.subtle.importKey('raw', keyHash, {name:'HMAC', hash:'SHA-256'}, false, ['sign']);
      const canonical = [method, url.pathname + url.search, timestamp, nonce, bodyHash].join('\n');
      const signature = hex(await crypto.subtle.sign('HMAC', key, bytes(canonical)));
      const headers = new Headers(options.headers || (resource instanceof Request ? resource.headers : {}));
      headers.set('X-CL-Device', device.device_id); headers.set('X-CL-Timestamp', timestamp);
      headers.set('X-CL-Nonce', nonce); headers.set('X-CL-Signature', signature);
      options = {...options, headers};
    }
    if(url.pathname.startsWith('/show-info/')&&!['GET','HEAD','OPTIONS'].includes(method)){
      const headers=new Headers(options.headers||(resource instanceof Request?resource.headers:{}));
      window.CLRemoteAuthDiagnostic={...diagnostic(),request:{method,path:url.pathname,origin:url.origin,device_id:/^[a-f0-9]{32}$/.test(headers.get('X-CL-Device')||'')?headers.get('X-CL-Device'):null,headers:Object.fromEntries(headerNames.map(name=>[name,headers.has(name)]))}};
      refreshDiagnostic();
    }
    const response = await original(resource, options);
    if(response.status===403&&url.pathname.startsWith('/show-info/')){
      const data=await response.clone().json().catch(()=>({}));
      window.CLRemoteAuthDiagnostic.response={status:403,error:data.message||data.error||null,server:data.auth_diagnostic||null};
      refreshDiagnostic();
    }

    if (response.status === 403 && url.pathname === '/action') {
      const result = await response.clone().json().catch(() => ({}));
      const status = document.getElementById('cl-remote-security-status');
      if (status) status.textContent = result.error || 'Commande refusée';
    }
    return response;
  };
  document.addEventListener('DOMContentLoaded', () => {
    const zone = document.createElement('div'); zone.id = 'cl-remote-security-status';
    zone.style.cssText = 'font:11px system-ui;padding:6px 8px;border:1px solid #535b69;border-radius:6px;margin:8px 5px 5px;color:inherit;text-align:center;line-height:1.4;overflow-wrap:anywhere';
    const details=document.createElement('details'),summary=document.createElement('summary'),pre=document.createElement('pre');
    summary.textContent='Diagnostic d’appairage — sans secret';pre.id='cl-remote-auth-diagnostic';pre.style.cssText='white-space:pre-wrap;overflow-wrap:anywhere;text-align:left;font-size:12px';details.append(summary,pre);
    refreshDiagnostic();
    const paired = credential();
    zone.textContent = paired ? 'Télécommande appairée — vérification…' : 'Télécommandes : appairage requis pour le contrôle distant';
    if (['localhost','127.0.0.1','[::1]'].includes(location.hostname)) {
      const link = document.createElement('a'); link.href='/security/panel'; link.target='_blank';
      link.textContent=' — Gérer / QR / Désarmer'; zone.append(link);
    }
    // Shared by mobile and desktop remotes: keep administration beside
    // the product baseline instead of above the playback controls.
    const footer = document.querySelector('footer.v2-statusbar');
    if (footer) footer.before(zone);
    else document.body.append(zone);
    zone.after(details);refreshDiagnostic();
    if (paired) {
      const heartbeat = async () => {
        try {
          const response = await fetch('/remote/heartbeat', {method:'POST',body:'{}',headers:{'Content-Type':'application/json'}});
          const state = await response.json();
          if(response.ok) window.CLRemotePermissions={...state.permissions,posts:state.posts||[]};
          zone.textContent = response.ok ? `TÉLÉCOMMANDES ${state.armed ? '● ARMÉES' : '○ DÉSARMÉES'} — ${state.role} — ${JSON.parse(paired).authorization_type==='permanent'?'permanente':'temporaire'}` : state.error;
        } catch (_) { zone.textContent='Télécommande : serveur inaccessible'; }
      };
      heartbeat(); setInterval(heartbeat, 4000);
    }
  });
})();
