/* Read-only projection of already accepted UI state. Does not wrap applyStatus,
   fetch, command handlers, generation guards or polling. Own DOM nodes only. */
(() => {
  'use strict';
  const app = document.querySelector('.v2-app[data-module]');
  if (!app) return;
  const module = app.dataset.module;
  const current = app.querySelector('.sc-current');
  const next = app.querySelector('.sc-next');
  const status = document.getElementById('status');
  const text = (node, value) => { if (node && node.textContent !== value) node.textContent = value; };
  const data = (node, key, value) => { if (node && node.dataset[key] !== value) node.dataset[key] = value; };
  const modern = () => document.body.dataset.skin && document.body.dataset.skin !== 'original';
  const acceptedState = () => {
    if (module === 'session') return typeof lastKnownState !== 'undefined' ? lastKnownState : null;
    if (module === 'ab') return typeof lastKnownAbState !== 'undefined' ? lastKnownAbState : null;
    return typeof lastState !== 'undefined' ? lastState : null;
  };
  const previousTitles = new WeakMap();
  function project() {
    const state = acceptedState();
    const online = Boolean(state && state.connected && !status.classList.contains('disconnected'));
    let transport = 'neutral';
    if (state) {
      if (!online) transport = 'offline';
      else if (module === 'session') transport = current.classList.contains('session-paused') ? 'paused' : current.classList.contains('session-playing') ? 'playing' : 'stopped';
      else if (module === 'arrangement') transport = current.classList.contains('is-paused') ? 'paused' : current.classList.contains('is-playing') ? 'playing' : 'stopped';
      // A/B is-playing also remembers a launch; the accepted transport disambiguates it.
      else transport = state.is_paused ? 'paused' : state.is_playing ? 'playing' : 'stopped';
    }
    data(current, 'uiState', transport);
    text(current && current.querySelector('.sc-state-badge'), {neutral:'CONNEXION',offline:'HORS LIGNE',playing:'PLAYING',paused:'PAUSE',stopped:'STOPPED'}[transport]);
    const nextState = next.classList.contains('is-imminent') ? 'imminent' : next.classList.contains('is-prepared') ? 'ready' : 'selected';
    data(next, 'uiState', nextState);
    text(next.querySelector('.sc-state-badge'), nextState === 'ready' ? 'READY' : nextState === 'imminent' ? 'IMMINENT' : 'SELECTED');
    for (const mirror of app.querySelectorAll('[data-time-source]')) {
      const source = document.getElementById(mirror.dataset.timeSource);
      const raw = source ? source.textContent : '';
      const times = raw.match(/(?:\d{1,2}:)?\d{1,2}:\d{2}|--:--/g);
      let value = times && times.length ? times[times.length - 1] : '--:--';
      if (/^\d:\d\d$/.test(value)) value = '0' + value;
      const caption = /restant/i.test(raw) ? 'RESTANT' : /durée/i.test(raw) ? 'DURÉE' : /temps en cours/i.test(raw) ? 'ÉCOULÉ' : /début/i.test(raw) ? 'DÉBUT' : 'TEMPS';
      text(mirror.querySelector('strong'), value);
      text(mirror.querySelector('.sc-time-label'), caption);
    }
    const position = document.getElementById('position');
    if (position) {
      const label = position.textContent.trim().toUpperCase();
      data(app, 'uiDeck', label === 'A' ? 'a' : label === 'B' ? 'b' : 'mix');
    }
    for (const card of [current, next]) {
      const title = card.querySelector('.sc-title');
      const value = title.textContent;
      const previous = previousTitles.get(title);
      if (modern() && previous !== undefined && previous !== value && value !== '—' && title.animate) {
        if (title._presentationFlash) title._presentationFlash.cancel();
        title._presentationFlash = title.animate([{filter:'brightness(1.45)'},{filter:'brightness(1)'}],{duration:450});
      }
      previousTitles.set(title,value);
    }
  }
  // Observe source DOM only. Attribute filter excludes the projection's data-ui-*.
  const observer = new MutationObserver(project);
  for (const node of [current,next,status,document.getElementById('abPauseResume'),document.getElementById('position')]) {
    if (node) observer.observe(node,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['class']});
  }
  project();
  const go = app.querySelector('.go-button, #abSceneConfirm, #goBtn');
  function showGoRequest() {
    if (!modern() || !go || go.disabled) return;
    const badge = current.querySelector('.sc-go-feedback');
    if (badge._requestAnimation) badge._requestAnimation.cancel();
    badge._requestAnimation = badge.animate([{opacity:0},{opacity:1,offset:.12},{opacity:1,offset:.75},{opacity:0}],{duration:1200});
  }
  if (go) go.addEventListener('click',showGoRequest, {capture:true});
  document.addEventListener('keydown', event => {
    // Existing handler decides whether Enter was accepted; no second command is sent.
    if (event.key === 'Enter' && event.defaultPrevented && !event.repeat &&
        !event.target.closest('input,select,textarea,[contenteditable="true"]')) showGoRequest();
  });
})();
