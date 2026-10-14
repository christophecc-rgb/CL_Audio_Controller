/* Dedicated local control: only confirmed backend state drives the cards. */
(function (root) {
  'use strict';
  function createLightController({document, fetch, setTimeout, clearTimeout, crypto}) {
    let snapshot = null, pending = false, error = '', timer = null, serial = 0, accepted = 0, stopped = false, hasPlayed = false, reachable = false;
    const node = id => document.getElementById(id);
    const buttons = Array.from(document.querySelectorAll('[data-action]'));
    const remoteToggle = node('remote-toggle');
    const remoteState = node('remote-state');

    const hostname = root.location && root.location.hostname
      ? String(root.location.hostname).toLowerCase()
      : '';

    const localInterface =
      hostname === '127.0.0.1' ||
      hostname === 'localhost' ||
      hostname === '::1' ||
      hostname === '';
    const title = value => String(value || '').normalize('NFC').trim();

    const displayTitle = value => {
      let text = title(value);
      if (!text) return '';

      // Retire le préfixe de scène humain : "13 - ", "25 - ", etc.
      text = text.replace(/^\s*\d+\s*-\s*/, '');

      // Coupe les métadonnées techniques après le premier ";"
      text = text.split(';', 1)[0].trim();

      // Nettoie quelques suffixes techniques usuels visibles dans les titres.
      text = text
        .replace(/\s*-\s*VIDEO\s*-?\s*$/i, '')
        .replace(/\s*-\s*VIDEO\s*$/i, '')
        .replace(/\s*-+\s*$/g, '')
        .trim();

      return text;
    };
    const time = value => {
      if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return '—';
      const seconds = Math.floor(value);
      return String(Math.floor(seconds/60)).padStart(2,'0') + ':' + String(seconds%60).padStart(2,'0');
    };
    function render() {
      const available = snapshot && snapshot.ableton_available && snapshot.set_available;
      const state = error ? 'error' : !available ? 'unavailable' : snapshot.is_playing ? 'playing' : hasPlayed ? 'stopped' : 'ready';
      node('state').textContent = {error:'ERREUR',unavailable:'ABLETON INDISPONIBLE',playing:'LECTURE',ready:'PRÊT',stopped:'ARRÊTÉ'}[state];
      node('state').dataset.state = state;

      const currentCard = document.querySelector('.scene.current');
      if (currentCard) {
        currentCard.classList.toggle(
          'is-playing',
          Boolean(available && snapshot && snapshot.is_playing && Number.isInteger(snapshot.current_scene))
        );
      }
      const currentIndex = snapshot && snapshot.current_scene;
      const currentName = snapshot && snapshot.current_scene_name;
      const preparedIndex = snapshot && snapshot.prepared_scene;
      const preparedName = snapshot && snapshot.prepared_scene_name;

      node('current-number').textContent =
        Number.isInteger(currentIndex) ? String(currentIndex + 1).padStart(2, '0') : '—';

      node('current-name').textContent =
        displayTitle(currentName) || 'Aucune scène en cours';

      node('prepared-number').textContent =
        Number.isInteger(preparedIndex) ? String(preparedIndex + 1).padStart(2, '0') : '—';

      node('prepared-name').textContent =
        displayTitle(preparedName) || (available ? 'Aucune scène préparée' : 'En attente d’Ableton');
      for (const [id, field] of [['current-position','current_position_seconds'],['current-duration','current_duration_seconds'],['current-remaining','current_remaining_seconds']]) {
        node(id).textContent = time(available && snapshot.is_playing && Number.isInteger(snapshot.current_scene) ? snapshot[field] : null);
      }
      if (node('prepared-duration')) node('prepared-duration').textContent = time(available ? snapshot.prepared_duration_seconds : null);
      const remoteEnabled = Boolean(snapshot && snapshot.remote_enabled);
      const commandsAllowedHere = localInterface || remoteEnabled;

      buttons.forEach(button => {
        button.disabled =
          pending ||
          !reachable ||
          !available ||
          !commandsAllowedHere ||
          !snapshot.allowed_actions.includes(button.dataset.action);
      });

      if (remoteToggle) {
        remoteToggle.hidden = !localInterface;
        remoteToggle.disabled = pending || !reachable;
        if (remoteToggle.classList && typeof remoteToggle.classList.toggle === 'function') {
          remoteToggle.classList.toggle('is-enabled', remoteEnabled);
        }
        if (typeof remoteToggle.setAttribute === 'function') {
          remoteToggle.setAttribute('aria-pressed', remoteEnabled ? 'true' : 'false');
        }
      }

      if (remoteState) remoteState.textContent = remoteEnabled ? 'ON' : 'OFF';

      const pauseLabel = node('pause-label');
      if (pauseLabel) {
        pauseLabel.textContent =
          snapshot && snapshot.is_paused ? 'REPRENDRE' : 'PAUSE';
      }

      node('go').setAttribute('aria-busy', String(pending));

      const remoteMessage =
        (!localInterface && !remoteEnabled)
          ? 'Télécommande désactivée sur le Mac'
          : '';

      node('message').textContent =
        error ||
        (pending ? 'Commande en cours…' : remoteMessage);
    }
    function apply(state, order) {
      if (!state || !Number.isInteger(state.set_generation)) throw new Error('Réponse de statut invalide');
      if (order < accepted || (snapshot && state.set_generation < snapshot.set_generation)) return false;
      if (!snapshot || state.set_generation !== snapshot.set_generation) hasPlayed = false;
      if (state.is_playing) hasPlayed = true;
      accepted = order; snapshot = state; render(); return true;
    }
    async function timedFetch(url, options) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 4000);
      try { return await fetch(url, {...options, signal:controller.signal}); } finally { clearTimeout(timeout); }
    }
    async function responseData(response) {
      let data;
      try { data = await response.json(); } catch (_) { throw new Error('Réponse illisible du serveur'); }
      if (!response.ok) {
        const failure = new Error('Erreur '+response.status+' — '+(data.message || data.error || 'Commande refusée'));
        failure.status = response.status; failure.data = data; throw failure;
      }
      return data;
    }
    async function poll() {
      const order = ++serial;
      try {
        const data = await responseData(await timedFetch('/status', {cache:'no-store'}));
        if (apply(data, order)) { reachable = true; error = ''; render(); }
      } catch (failure) { if (order >= accepted) { reachable = false; error = failure.message; buttons.forEach(b => { b.disabled=true; }); node('state').textContent='ERREUR'; node('state').dataset.state='error'; node('message').textContent=error; } }
    }
    function requestId() {
      if (crypto && typeof crypto.randomUUID === 'function') {
        return crypto.randomUUID();
      }

      if (crypto && typeof crypto.getRandomValues === 'function') {
        const bytes = new Uint8Array(16);
        crypto.getRandomValues(bytes);
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        const hex = Array.from(bytes, value => value.toString(16).padStart(2, '0'));
        return [
          hex.slice(0,4).join(''),
          hex.slice(4,6).join(''),
          hex.slice(6,8).join(''),
          hex.slice(8,10).join(''),
          hex.slice(10,16).join('')
        ].join('-');
      }

      return 'light-' + Date.now() + '-' + Math.random().toString(36).slice(2);
    }

    function flashPrepared() {
      const card = document.querySelector('.scene.prepared');
      if (!card) return;

      card.classList.remove('selection-flash');

      // Force un nouveau cycle d'animation même lors d'appuis rapprochés.
      void card.offsetWidth;

      card.classList.add('selection-flash');

      setTimeout(() => {
        card.classList.remove('selection-flash');
      }, 620);
    }

    async function action(kind) {
      const button = buttons.find(b => b.dataset.action === kind);
      if (!button || button.disabled || pending) return;
      pending = true; error = ''; render(); const order = ++serial;

      try {
        const payload = {action:kind, set_generation:snapshot.set_generation};
        if (kind === 'go') {
          payload.request_id = requestId();
          payload.scene = snapshot.prepared_scene + 1;
        }
        const data = await responseData(await timedFetch('/action', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}));
        if (data.ok !== true) throw new Error(data.message || 'Commande refusée');

        const applied = apply(data.state, order);

        if (applied && kind === 'stop' && !data.state.is_playing) {
          hasPlayed = true;
        }

        if (applied && (kind === 'prev' || kind === 'next')) {
          flashPrepared();
        }
      } catch (failure) {
        if (failure.status === 409) { if (failure.data.state) apply(failure.data.state, order); await poll(); }
        error = failure.message;
      } finally { pending = false; render(); }
    }
    buttons.forEach(button => button.addEventListener('click', () => action(button.dataset.action)));

    if (remoteToggle) {
      remoteToggle.addEventListener('click', async () => {
        if (!localInterface || pending) return;

        pending = true;
        error = '';
        render();

        const order = ++serial;
        const enabled = !(snapshot && snapshot.remote_enabled);

        try {
          const data = await responseData(await timedFetch('/light/remote', {
            method: 'POST',
            headers: {'Content-Type':'application/json'},
            body: JSON.stringify({enabled}),
          }));

          if (data.state) apply(data.state, order);
        } catch (failure) {
          error = failure.message;
        } finally {
          pending = false;
          render();
        }
      });
    }

    const held = new Set();
    document.addEventListener('keydown', event => {
      const kind = {
        Enter:'go',
        ArrowLeft:'prev',
        ArrowRight:'next',
        Escape:'stop',
        ' ':'pause',
        Spacebar:'pause'
      }[event.key];
      if (!kind || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || /INPUT|TEXTAREA|SELECT/.test(event.target.tagName) || event.target.isContentEditable) return;
      event.preventDefault(); if (event.repeat || held.has(event.key)) return;
      held.add(event.key); action(kind);
    });
    document.addEventListener('keyup', event => held.delete(event.key));
    root.addEventListener && root.addEventListener('blur', () => held.clear());
    async function tick() { if(stopped) return; if(!pending) await poll(); if(!stopped) timer=setTimeout(tick,750); }
    render();
    return {action,poll,start:tick,stop(){stopped=true;clearTimeout(timer);},getState:()=>snapshot};
  }
  if (typeof module !== 'undefined') module.exports = {createLightController};
  else createLightController({document:root.document,fetch:root.fetch.bind(root),setTimeout:root.setTimeout.bind(root),clearTimeout:root.clearTimeout.bind(root),crypto:root.crypto}).start();
})(typeof window !== 'undefined' ? window : globalThis);
