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

/* ShowCue mobile conduite: data-driven rows, one dock, no DOM repair polling. */
(() => {
  const mobile = window.matchMedia('(max-width:760px)');
  const view = document.getElementById('view-conduite');
  const sequence = document.getElementById('timed-sequence');
  const nav = document.querySelector('.stage-navigation');
  if (!view || !sequence || !nav) return;
  const posts = Object.keys(destinationLabels);
  const node = (tag, className, text) => {
    const el = document.createElement(tag);
    el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  };
  const button = (className, text, action) => {
    const el = node('button', className, text);
    el.type = 'button';
    el.onclick = action;
    return el;
  };
  const knownPosts = cue => Array.isArray(cue.posts) && cue.posts.length > 0 &&
    cue.posts.every(post => posts.includes(post));
  const roleLabel = cue => !knownPosts(cue) ? 'POSTES ?' :
    posts.every(post => cue.posts.includes(post)) ? 'TOUT' :
      posts.filter(post => cue.posts.includes(post)).map(post => destinationLabels[post]).join(' · ');

  const filter = node('label', 'stage-conduite-filter');
  const filterSelect = node('select', '');
  filterSelect.id = 'stage-conduite-filter-select';
  filterSelect.setAttribute('aria-label', 'Filtrer la conduite par poste');
  filterSelect.append(new Option('AUTO', 'auto'), new Option('TOUT', 'all'));
  filter.append(node('span', '', 'AFFICHER'), filterSelect);
  document.getElementById('section-filters').after(filter);

  const roleEditor = node('dialog', 'stage-role-editor');
  roleEditor.id = 'stage-role-editor';
  roleEditor.setAttribute('aria-labelledby', 'stage-role-heading');
  const heading = node('h2', '', 'Affecter ce cue');
  heading.id = 'stage-role-heading';
  const cueTitle = node('p', 'stage-role-cue-title');
  const options = node('div', 'stage-role-options');
  const error = node('p', 'error');
  error.setAttribute('role', 'alert');
  const actions = node('div', 'actions');
  let editState = null;
  let saving = false;
  const close = () => { if (!saving) roleEditor.close(); };
  const cancel = button('', 'ANNULER', close);
  const modify = button('quiet', 'TEXTE / TC', () => {
    const cue = editState?.cue;
    close();
    if (cue) openEditor(cue);
  });
  const save = button('primary', 'TERMINER', async () => {
    if (!editState || saving) return;
    const state = editState;
    if (!state.selected.size) { error.textContent = 'Choisissez au moins un poste.'; return; }
    const nextPosts = posts.filter(post => state.selected.has(post));
    saving = true;
    [...actions.children, ...options.children].forEach(el => el.disabled = true);
    try {
      if (!knownPosts(state.cue) || JSON.stringify([...state.cue.posts].sort()) !== JSON.stringify([...nextPosts].sort())) {
        await api('/show-info/cues/' + encodeURIComponent(state.cue.id), {
          method: 'PUT', body: JSON.stringify(scoped({posts: nextPosts}, state.sessionId))
        });
      }
      roleEditor.close();
      await refresh();
    } catch (failure) { error.textContent = failure.message; }
    finally {
      saving = false;
      [...actions.children, ...options.children].forEach(el => el.disabled = false);
    }
  });
  actions.append(modify, cancel, save);
  roleEditor.append(heading, cueTitle, options, error, actions);
  document.body.append(roleEditor);
  roleEditor.addEventListener('cancel', event => { if (saving) event.preventDefault(); });
  roleEditor.addEventListener('close', () => { editState = null; });
  function paintOptions() {
    [...options.children].forEach(el => {
      const active = el.dataset.post === 'all' ? posts.every(post => editState.selected.has(post)) : editState.selected.has(el.dataset.post);
      el.classList.toggle('active', active);
      el.setAttribute('aria-pressed', String(active));
    });
  }
  function openRoles(cue) {
    editState = {cue, sessionId: snapshot.active_session_id, selected: new Set(Array.isArray(cue.posts) ? cue.posts.filter(post => posts.includes(post)) : [])};
    cueTitle.textContent = cue.text;
    error.textContent = knownPosts(cue) ? '' : 'Affectation inconnue : choisissez les postes à enregistrer.';
    options.replaceChildren();
    [['all', 'TOUT'], ...Object.entries(destinationLabels)].forEach(([post, label]) => {
      const option = button('', label, () => {
        if (post === 'all') editState.selected = new Set(posts);
        else if (editState.selected.has(post)) editState.selected.delete(post);
        else editState.selected.add(post);
        paintOptions();
      });
      option.dataset.post = post;
      options.append(option);
    });
    paintOptions();
    roleEditor.showModal();
  }

  // Decorate before attachment. Keep the existing row and its native drag handlers.
  const baseCueLine = cueLine;
  cueLine = function(cue, position) {
    const source = mobile.matches && !Array.isArray(cue.posts) ? {...cue, posts: []} : cue;
    const row = baseCueLine(source, position);
    if (!mobile.matches || cue.status !== 'official' || cue.mode === 'library') return row;
    row.classList.add('stage-mobile-cue');
    row.hidden = filterSelect.value !== 'all' && knownPosts(cue) && posts.includes(postEl.value) && !cue.posts.includes(postEl.value);
    const time = node('span', 'stage-cue-time', isTimecode(cue.timecode) ? cue.timecode : '—');
    const title = node('span', 'stage-cue-title', cue.text);
    title.title = cue.text;
    const summary = button('stage-cue-roles', roleLabel(cue), () => openRoles(cue));
    summary.setAttribute('aria-label', 'Affecter ' + cue.text + ' : ' + roleLabel(cue));
    row.replaceChildren(time, title, summary);
    return row;
  };

  let gesture = null;
  let dragging = false;
  let suppressClick = false;
  const active = () => mobile.matches && view.classList.contains('active');
  sequence.addEventListener('pointerdown', event => {
    if (!active() || !event.isPrimary || event.button !== 0) return;
    const row = event.target.closest('.stage-mobile-cue');
    if (!row) return;
    suppressClick = false;
    gesture = {row, id: event.pointerId, x: event.clientX, y: event.clientY, started: performance.now(), moved: false};
  }, {passive: true});
  sequence.addEventListener('pointermove', event => {
    if (gesture && event.pointerId === gesture.id && Math.hypot(event.clientX - gesture.x, event.clientY - gesture.y) > 10) gesture.moved = true;
  }, {passive: true});
  window.addEventListener('pointercancel', () => { gesture = null; suppressClick = true; });
  sequence.addEventListener('dragstart', () => { dragging = true; gesture = null; suppressClick = true; });
  sequence.addEventListener('dragend', () => { dragging = false; });
  window.addEventListener('pointerup', event => {
    if (!gesture || event.pointerId !== gesture.id) return;
    suppressClick = gesture.moved || performance.now() - gesture.started > 400 || dragging;
    gesture = null;
  }, {passive: true});
  // Capture before the older desktop selection listeners; never cancel drag events.
  view.addEventListener('click', event => {
    if (!active()) return;
    const row = event.target.closest('.stage-mobile-cue');
    if (!row) return;
    event.stopImmediatePropagation();
    if (suppressClick || dragging) { event.preventDefault(); return; }
    const cue = conduiteOrderedCues().find(item => item.id === row.dataset.cueId);
    if (cue) openRoles(cue);
  }, true);
  const baseInteractionActive = interactionActive;
  interactionActive = function() {
    return baseInteractionActive() || roleEditor.open || (mobile.matches && (Boolean(gesture) || dragging));
  };

  const baseSequence = renderSequence;
  renderSequence = function(...args) {
    // The desktop section selection remains intact when returning to desktop.
    const previousSection = sectionFilter;
    if (mobile.matches) sectionFilter = 'TOUT';
    try { return baseSequence(...args); }
    finally { sectionFilter = previousSection; }
  };
  const updateFilter = () => {
    filterSelect.options[0].textContent = 'AUTO · ' + (destinationLabels[postEl.value] || 'POSTE') + ' + TOUT';
    renderSequence();
  };
  filterSelect.addEventListener('change', updateFilter);
  postEl.addEventListener('change', updateFilter);

  const dock = node('div', 'stage-conduite-dock');
  dock.id = 'stage-conduite-dock';
  const dockTitle = node('strong', 'stage-dock-title');
  const dockTimes = node('span', 'stage-dock-times');
  dock.append(dockTitle, dockTimes, button('stage-dock-add', '+ CUE', () => document.getElementById('add-cue').click()));
  document.body.append(dock);
  function updateDock(data) {
    dockTitle.textContent = data.title || 'SCÈNE —';
    dockTitle.title = data.title || 'Scène Ableton';
    dockTimes.textContent = `${formatSeconds(data.elapsed_seconds)} / ${formatSeconds(data.scene_duration_seconds)} · R ${formatSeconds(data.remaining_seconds)}`;
  }
  const baseRender = render;
  render = function(data) { baseRender(data); updateDock(data); };

  let lastY = window.scrollY;
  function updateVisibility() {
    dock.hidden = !active();
    nav.classList.remove('stage-nav-hidden');
    lastY = window.scrollY;
    if (!active() && roleEditor.open) close();
  }
  const baseSetView = setView;
  setView = function(...args) { baseSetView(...args); updateVisibility(); };
  window.addEventListener('scroll', () => {
    const y = Math.max(0, Math.min(window.scrollY, document.documentElement.scrollHeight - window.innerHeight));
    const delta = y - lastY;
    if (active()) {
      if (delta > 0 && y > 80) nav.classList.add('stage-nav-hidden');
      else if (delta < 0 || y <= 0) nav.classList.remove('stage-nav-hidden');
    }
    lastY = y;
  }, {passive: true});
  // Measure the real navigation, including Safari's safe area, only on resize.
  const measureNav = () => dock.style.setProperty('--stage-nav-height', nav.getBoundingClientRect().height + 'px');
  const navSize = new ResizeObserver(measureNav);
  navSize.observe(nav);
  mobile.addEventListener('change', () => { gesture = null; dragging = false; updateFilter(); updateVisibility(); measureNav(); });
  updateFilter();
  updateDock(snapshot);
  updateVisibility();
  measureNav();
})();
