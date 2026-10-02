(() => {
  const code = new URLSearchParams(location.hash.slice(1)).get('code');
  history.replaceState(null,'',location.pathname);
  const status = document.getElementById('status');
  const button = document.getElementById('pair');
  if (!code) { status.textContent='QR absent. Scanner un nouveau QR sur le serveur.'; button.disabled=true; }
  button.onclick = async () => {
    button.disabled=true;
    try {
      const response=await fetch('/remote/pair/request',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,name:document.getElementById('name').value,operator:document.getElementById('operator').value})});
      const pending=await response.json(); if (!response.ok) throw new Error(pending.error);
      status.textContent='En attente de validation sur le serveur…';
      const until=Date.now()+300000;
      const poll=async () => {
        if (Date.now()>until) { status.textContent='Demande expirée. Scanner un nouveau QR.'; return; }
        try {
          const result=await fetch('/remote/pair/claim',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(pending)});
          const device=await result.json(); if (!result.ok) throw new Error(device.error);
          if (device.pending) { setTimeout(poll,2000); return; }
          const key='cl-paired-device-v1';
          const remember=device.authorization_type==='permanent' && document.getElementById('remember').checked;
          // A permanent server grant never implies browser persistence without consent.
          if (remember) {
            try { localStorage.setItem(key,JSON.stringify(device)); sessionStorage.removeItem(key); }
            catch (_) {
              sessionStorage.setItem(key,JSON.stringify(device));
              alert('Le navigateur ne permet pas la mémorisation permanente. Cet onglet reste autorisé ; après sa fermeture, un nouvel appairage sera nécessaire.');
            }
          } else {
            try { localStorage.removeItem(key); } catch (_) { /* Temporary sessions need no localStorage. */ }
            sessionStorage.setItem(key,JSON.stringify(device));
          }
          location.replace(device.role==='reader'?'/show-info':'/');
        } catch(error) { status.textContent=error.message; }
      }; poll();
    } catch(error) { status.textContent=error.message; }
  };
})();
