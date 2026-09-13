/* ShowCue responsive stage view; all controls retain the existing backend. */
(() => {
  const live = document.getElementById('view-live');
  if (!live) return;
  document.body.classList.add('stage-ui');
  const node = (tag, cls, text) => {
    const el = document.createElement(tag);
    el.className = cls;
    if (text !== undefined) el.textContent = text;
    return el;
  };
  const header = document.querySelector('.topbar');
  const brand = node('div', 'stage-brand');
  brand.innerHTML = '<span class="stage-wave" aria-hidden="true">▂▆█▅▂</span><div>CL ShowCue<small>LE SPECTACLE EN TEMPS RÉEL</small></div>';
  const context = node('div', 'stage-context');
  for (const id of ['session', 'post']) {
    const label = node('label', 'stage-field', id === 'session' ? 'Spectacle' : 'Poste');
    label.append(document.getElementById(id));
    context.append(label);
  }
  const clocks = node('div', 'stage-clocks');
  clocks.append(document.getElementById('ltc'));
  const sync = node('small', 'stage-sync', 'LTC · En attente');
  clocks.append(sync);
  const transport = node('div', 'stage-transport');
  transport.append(document.getElementById('transport'), document.getElementById('call-button'));
  const network = document.querySelector('.v6-network-slot');
  const nav = document.querySelector('.v6-navigation');
  const logo = document.querySelector('.v6-logo');
  const clock = document.getElementById('server-clock').parentElement;
  const title = document.getElementById('title');
  header.className = 'stage-header';
  header.replaceChildren(brand, context, transport, clocks);
  nav.className = 'stage-navigation';
  document.querySelector('.shell').prepend(nav);
  const utilities = node('details', 'stage-utilities');
  utilities.append(node('summary', '', 'Connexion et horloge'), network, clock);
  nav.append(utilities);
  header.append(title);

  /* Horloge et menu mobile v1 */
  const clockSlot = node('div', 'stage-wall-clock');
  clockSlot.append(node('small', '', 'HEURE'));
  clockSlot.append(document.getElementById('server-clock'));

  const more = node('button', 'stage-more', '⋯');
  more.type = 'button';
  more.setAttribute('aria-label', 'Spectacle, sessions et connexion');

  const menu = node('dialog', 'stage-mobile-menu');
  menu.id = 'stage-mobile-menu';
  more.setAttribute('aria-controls', menu.id);

  const menuHeading = node('div', 'stage-menu-heading');
  const closeMenu = node('button', '', 'Fermer');
  closeMenu.type = 'button';
  menuHeading.append(node('strong', '', 'Spectacle et connexion'), closeMenu);
  menu.append(menuHeading);
  document.body.append(menu);

  more.onclick = () => menu.showModal();
  closeMenu.onclick = () => menu.close();

  const sessionField = document.getElementById('session').parentElement;
  const secondary = nav.querySelector('.v6-secondary-actions');
  const utilitySummary = utilities.querySelector('summary');
  utilitySummary.textContent = 'Connexion';

  const mobile = window.matchMedia('(max-width:760px)');
  function arrangeHeader() {
    if (mobile.matches) {
      transport.append(clockSlot, more);
      menu.append(sessionField);
      if (secondary) menu.append(secondary);
      menu.append(utilities);
      utilities.open = true;
    } else {
      if (menu.open) menu.close();
      /* Desktop harmonise v1 */
      nav.prepend(clockSlot);
      more.remove();
      clockSlot.append(document.getElementById('server-clock'));
      context.prepend(sessionField);
      if (secondary) nav.append(secondary);
      nav.append(utilities);
    }
    if (mobile.matches) {
      clockSlot.append(document.getElementById('server-clock'));
    }
  }
  mobile.addEventListener('change', arrangeHeader);
  arrangeHeader();

  const banner = node('div', 'stage-banner');
  logo.className = 'stage-logo';
  banner.append(logo);
  header.after(banner);

  /* Desktop logo net et horloge laterale v2 */
  const desktopLogo = logo.cloneNode(true);
  desktopLogo.className = 'stage-desktop-logo';
  header.append(desktopLogo);

  const desktopSignals = node('div', 'stage-desktop-signals');

  function arrangeDesktopSignals() {
    if (mobile.matches) {
      header.append(clocks, transport);
      desktopSignals.remove();
    } else {
      desktopSignals.append(clocks, transport);
      header.append(desktopSignals);
    }
  }
  mobile.addEventListener('change', arrangeDesktopSignals);
  arrangeDesktopSignals();

  const lane = node('div', 'stage-lane');
  const side = node('aside', 'stage-side');
  const heading = node('div', 'stage-live-heading');
  heading.innerHTML = '<strong>LIVE</strong><span>Suivi des cues en temps réel</span>';
  const past = live.querySelector('.live-past');
  const current = live.querySelector('.live-current');
  const checklist = document.getElementById('live-untimed-checklist');
  lane.append(heading, live.querySelector('.ableton-strip'), past, current);
  if (checklist) lane.append(checklist);
  side.append(live.querySelector('.live-ahead'));
  const orderPanel = node('article', 'panel stage-order');
  const orderHead = node('div', 'stage-order-head');
  const seeAll = node('button', 'quiet', 'Voir tout ›');
  seeAll.onclick = () => setView('conduite');
  orderHead.append(node('strong', '', 'Ordre du spectacle'), seeAll);
  const order = node('div', 'stage-order-list');
  orderPanel.append(orderHead, order);
  side.append(orderPanel);
  const quick = node('section', 'panel stage-quick');
  quick.append(node('div', 'stage-quick-title', 'Actions rapides'));
  const actions = node('div', 'stage-actions');
  for (const [symbol, label, sub, cls, action] of [
    ['＋', 'Ajouter un repère', 'Manuel ou LTC', 'green', () => document.getElementById('add-cue').click()],
    ['◇', 'Réserve', 'Texte de secours', 'gold', () => document.getElementById('add-library').click()],
    ['♩', 'Capture audio', 'Créer un brouillon', 'blue', () => document.getElementById('capture-audio').click()],
    ['▤', 'Notes', 'Note rapide', 'neutral', () => { captured = null; openEditor(null, 'manual'); }]
  ]) {
    const button = node('button', 'stage-action ' + cls);
    const copy = node('span', '');
    copy.append(node('strong', '', label), node('small', '', sub));
    const icon = node('span', 'stage-action-icon', symbol);
    icon.setAttribute('aria-hidden', 'true');
    button.append(icon, copy);
    button.onclick = action;
    actions.append(button);
  }
  quick.append(actions);
  live.append(lane, side, quick);
  const number = node('span', 'stage-number', '—');
  current.querySelector('.cue-kicker').prepend(number);
  const details = node('div', 'stage-details');
  const role = node('div', '');
  const notes = node('div', '');

  /* Notes editables et actions compactes v1 */
  notes.classList.add('stage-editable-notes');
  notes.tabIndex = 0;
  notes.setAttribute('role', 'button');
  notes.setAttribute('aria-label', 'Modifier les notes du cue actuel');
  notes.title = 'Toucher pour modifier les notes';

  let savingNotes = false;
  async function editCueNotes() {
    if (savingNotes) return;
    const cue = snapshot.current;
    const sessionId = snapshot.active_session_id;
    if (!cue) return;

    const value = window.prompt(
      'Notes du cue : ' + cue.text,
      cue.builder?.notes || ''
    );
    if (value === null) return;

    savingNotes = true;
    notes.setAttribute('aria-busy', 'true');
    try {
      await api('/show-info/cues/' + encodeURIComponent(cue.id), {
        method: 'PUT',
        body: JSON.stringify({
          session_id: sessionId,
          builder: {...(cue.builder || {}), notes: value}
        })
      });
      await refresh();
    } catch (error) {
      window.alert('Notes non enregistrées : ' + error.message);
    } finally {
      savingNotes = false;
      notes.removeAttribute('aria-busy');
    }
  }

  notes.onclick = editCueNotes;
  notes.onkeydown = event => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      editCueNotes();
    }
  };

  const shortLabels = ['Repère', 'Réserve', 'Audio', 'Brouillon'];
  actions.querySelectorAll('button').forEach((button, index) => {
    const label = button.querySelector('strong');
    if (label) label.textContent = shortLabels[index];
    button.setAttribute('aria-label', shortLabels[index]);
  });

  details.append(role, notes);
  current.querySelector('.current-copy').append(details);
  const numberFor = (cue, cues) => cue?.builder?.number || (cue && cues.findIndex(c => c.id === cue.id) >= 0 ? cues.findIndex(c => c.id === cue.id) + 1 : '—');
  function updateStage(data) {
    const cues = (data.conduite?.timed || []).filter(c => c.status === 'official');
    const cue = data.current;
    number.textContent = numberFor(cue, cues);
    current.classList.toggle('stage-has-current', Boolean(cue));
    sync.textContent = data.ltc_connected ? '● LTC · Synchronisé' : '○ LTC · Signal absent';
    sync.classList.toggle('connected', Boolean(data.ltc_connected));
    role.replaceChildren(node('small', '', 'Rôle / poste'), node('span', '', cue?.resolved?.role || cue?.builder?.role || data.post || '—'));
    notes.replaceChildren(node('small', '', 'Notes'), node('span', '', cue?.builder?.notes || 'Aucune note pour ce cue'));
    details.hidden = !cue;
    const index = cues.findIndex(c => c.id === (data.conduite_current_id || cue?.id));
    const start = Math.max(0, index - 2);
    order.replaceChildren();
    for (const [offset, item] of cues.slice(start, start + 8).entries()) {
      const pos = start + offset;
      const row = node('div', 'stage-order-row' + (pos === index ? ' active' : ''));
      if (pos === index) row.setAttribute('aria-current', 'step');
      row.append(node('span', 'stage-order-number', numberFor(item, cues)), node('span', 'stage-order-text', item.text), node('time', '', item.timecode || '—'), node('span', pos < index ? 'done' : '', pos < index ? '✓' : pos === index ? '▶' : '○'));
      order.append(row);
    }
    if (!cues.length) order.append(node('div', 'empty', 'Aucun cue dans cette session'));
  }
  const previousRender = render;
  render = function(data) { previousRender(data); updateStage(data); };
  if (snapshot && snapshot.ok) updateStage(snapshot);
})();

/* Appels directs desktop v1 */
(() => {
  const transport = document.querySelector('.stage-transport');
  const panel = document.getElementById('call-panel');
  if (!transport || !panel) return;

  const group = document.createElement('div');
  group.className = 'stage-direct-calls';
  group.setAttribute('role', 'group');
  group.setAttribute('aria-label', 'Appeler un poste');
  const buttons = [];

  panel.querySelectorAll('[data-call-target]').forEach(original => {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = original.textContent;
    button.title = 'Appeler ' + original.dataset.callTarget;
    button.setAttribute('aria-label', button.title);
    let pending = false;

    button.onclick = async () => {
      if (pending || original.disabled) return;
      pending = true;
      button.disabled = true;
      document.getElementById('call-error').textContent = '';
      try {
        await original.onclick();
        if (document.getElementById('call-error').textContent && !panel.open) {
          panel.showModal();
        }
      } finally {
        pending = false;
        button.disabled = original.disabled;
      }
    };

    buttons.push({button, original, busy: () => pending});
    group.append(button);
  });

  transport.append(group);

  const previousCalls = renderCalls;
  renderCalls = function(calls = {}) {
    previousCalls(calls);
    buttons.forEach(({button, original, busy}) => {
      const destination = original.dataset.callTarget;
      const states = (calls.outgoing || []).filter(
        item => item.destination === destination
      );
      button.disabled = busy() || original.disabled;
      button.classList.toggle(
        'direct-calling', states.some(item => item.state === 'calling')
      );
      button.classList.toggle(
        'direct-ok', states.some(item => item.state === 'acknowledged')
      );
    });
  };
  renderCalls(snapshot.calls || {});
})();
