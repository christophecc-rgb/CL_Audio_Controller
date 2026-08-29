(function (root) {
  'use strict';

  const FINAL_STATES = new Set(['confirmed', 'mismatch', 'timeout', 'idle']);

  function createController(options) {
    const applyState = options.applyState;
    const now = options.now || Date.now;
    const requestFrame = options.requestFrame || root.requestAnimationFrame.bind(root);
    const setTimer = options.setTimer || root.setTimeout.bind(root);
    const clearTimer = options.clearTimer || root.clearTimeout.bind(root);
    const waitingMs = options.waitingMs || 4000;
    const confirmedMs = options.confirmedMs || 500;

    let lastExpectedKey = null;
    let pendingFinalState = null;
    let pendingFinalKey = '';
    let waitingUntil = 0;
    let confirmedUntil = 0;
    let phase = 'idle';
    let timer = null;
    let generation = 0;
    let completedConfirmationKey = '';

    const cancelTimer = () => {
      if (timer !== null) clearTimer(timer);
      timer = null;
    };

    const rememberFinal = (backendState, finalKey) => {
      if (!FINAL_STATES.has(backendState)) return;
      pendingFinalState = backendState;
      pendingFinalKey = finalKey || '';
    };

    const showFinalState = () => {
      cancelTimer();
      const finalState = pendingFinalState || 'waiting';

      if (finalState === 'confirmed') {
        if (pendingFinalKey && completedConfirmationKey === pendingFinalKey) {
          phase = 'confirmed';
          applyState('confirmed');
          return;
        }
        phase = 'confirmed';
        confirmedUntil = now() + confirmedMs;
        applyState('confirmed');
        const confirmationGeneration = generation;
        timer = setTimer(() => {
          if (generation !== confirmationGeneration || phase !== 'confirmed') return;
          completedConfirmationKey = pendingFinalKey;
          applyState('confirmed');
        }, Math.max(0, confirmedUntil - now()));
        return;
      }

      phase = finalState;
      applyState(finalState);
    };

    const finishWaiting = (waitingGeneration) => {
      if (generation !== waitingGeneration) return;
      if (now() < waitingUntil) {
        timer = setTimer(() => finishWaiting(waitingGeneration), waitingUntil - now());
        return;
      }
      showFinalState();
    };

    const startWaiting = (expectedKey, expectedStartedAtMs, backendState, finalKey) => {
      generation += 1;
      cancelTimer();
      lastExpectedKey = expectedKey;
      pendingFinalState = null;
      pendingFinalKey = '';
      const reportedStart = Number(expectedStartedAtMs);
      waitingUntil = (Number.isFinite(reportedStart) && reportedStart > 0 ? reportedStart : now()) + waitingMs;
      confirmedUntil = 0;
      rememberFinal(backendState, finalKey);

      if (backendState === 'mismatch' || waitingUntil <= now()) {
        showFinalState();
        return;
      }
      phase = 'waiting-frame';

      // Cette affectation est synchrone : aucune réponse backend du même
      // cycle ne peut remplacer WAITING avant la première frame demandée.
      applyState('waiting');
      const waitingGeneration = generation;
      requestFrame(() => {
        if (generation !== waitingGeneration) return;
        phase = 'waiting';
        applyState('waiting');
        timer = setTimer(
          () => finishWaiting(waitingGeneration),
          Math.max(0, waitingUntil - now())
        );
      });
    };

    return {
      update({expectedKey, expectedStartedAtMs, hasExpected, backendState, finalKey}) {
        if (hasExpected && expectedKey !== lastExpectedKey) {
          startWaiting(expectedKey, expectedStartedAtMs, backendState, finalKey);
          return phase;
        }

        if (phase === 'waiting-frame' || phase === 'waiting') {
          if (backendState === 'mismatch') {
            generation += 1;
            cancelTimer();
            rememberFinal(backendState, finalKey);
            showFinalState();
            return phase;
          }
          rememberFinal(backendState, finalKey);
          if (now() >= waitingUntil) {
            showFinalState();
            return phase;
          }
          applyState('waiting');
          return 'waiting';
        }

        rememberFinal(backendState, finalKey);
        showFinalState();
        return phase;
      },
      snapshot() {
        return {lastExpectedKey, pendingFinalState, waitingUntil, confirmedUntil, phase};
      }
    };
  }

  const FALLBACK_PALETTES = {
    console_a: {base: '#C09AF2', accent: '#9B6BD6'},
    console_b: {base: '#63C7D4', accent: '#3E9EAC'}
  };

  function visibleDevices(devices, surface) {
    return (Array.isArray(devices) ? devices : []).filter(device => {
      if (!device || device.enabled === false) return false;
      const visibility = device.visibility || {};
      return visibility[surface] !== false;
    });
  }

  function devicesFromState(state) {
    if (state && Array.isArray(state.devices)) return state.devices;
    const midi = state && state.midi_console || {};
    return [
      {id:'console_a', legacy_key:'cl5', display_name:'CL5', enabled:true, library:'cl5', midi_channel:1,
       palette:FALLBACK_PALETTES.console_a, visibility:{show_control:true,remote:true,network_manager:true}, production_supported:true, ...(midi.cl5 || {})},
      {id:'console_b', legacy_key:'ql1', display_name:'QL1', enabled:true, library:'ql1', midi_channel:2,
       palette:FALLBACK_PALETTES.console_b, visibility:{show_control:true,remote:true,network_manager:true}, production_supported:true, ...(midi.ql1 || {})}
    ];
  }

  function deviceViewModel(device) {
    const palette = device.palette || FALLBACK_PALETTES[device.id] || {base:'#AEB5C0', accent:'#66707D'};
    const productionSupported = device.production_supported === true;
    const status = productionSupported ? (device.validation_status || device.status || 'unavailable') : 'unavailable';
    const showReturned = status === 'confirmed' || status === 'mismatch' || device.expected_scene_memory == null;
    const memory = (showReturned ? device.returned_scene_memory : device.expected_scene_memory) ?? '—';
    const hasLibrary = Boolean(device.library);
    const title = hasLibrary
      ? ((showReturned && device.returned_scene_memory != null ? device.returned_title : device.expected_title) || 'Titre non résolu')
      : '';
    return {
      id: String(device.id || ''),
      displayName: String(device.display_name || device.id || 'Device'),
      base: palette.base,
      accent: palette.accent,
      productionSupported,
      status,
      visualState: productionSupported ? (device.visual_state || 'idle') : 'idle',
      memory,
      title,
      expectedKey: [device.id || '', device.expected_midi_program ?? '', device.expected_activated_at ?? ''].join(':'),
      finalKey: [device.id || '', device.expected_midi_program ?? '', device.returned_midi_program ?? '', device.returned_at ?? ''].join(':'),
      expectedStartedAtMs: Number(device.expected_activated_at || 0) * 1000,
      hasExpected: productionSupported && device.expected_midi_program != null,
      label: productionSupported ? '' : 'Non actif en production'
    };
  }

  function renderDeviceCards(container, devices, options) {
    options = options || {};
    const surface = options.surface || 'remote';
    const prefix = options.idPrefix || 'device';
    const visible = visibleDevices(devices, surface);
    const retained = new Set();
    visible.forEach(device => {
      const view = deviceViewModel(device);
      retained.add(view.id);
      let card = Array.from(container.children).find(child => child.dataset.deviceId === view.id);
      if (!card) {
        card = root.document.createElement('div');
        card.className = 'midi-return state-idle';
        card.dataset.deviceId = view.id;
        card.innerHTML = '<div class="midi-return-heading"><span class="midi-return-console"></span><strong><span class="midi-return-memory">—</span></strong></div><span class="midi-return-main-title"></span><span class="midi-return-state"></span>';
        container.appendChild(card);
      }
      card.id = prefix + '-' + view.id;
      card.style.setProperty('--console-text', view.base);
      card.style.setProperty('--console-accent', view.accent);
      card.title = view.displayName;
      card.querySelector('.midi-return-console').textContent = view.displayName;
      card.querySelector('.midi-return-memory').textContent = view.memory;
      const title = card.querySelector('.midi-return-main-title');
      title.textContent = view.title;
      title.hidden = !view.title;
      if (!card._visualController) {
        card._visualController = createController({
          waitingMs: 4000,
          confirmedMs: 500,
          applyState: state => {
            ['idle','waiting','confirmed','mismatch','timeout'].forEach(item => card.classList.toggle('state-' + item, state === item));
          }
        });
      }
      const visual = card._visualController.update({
        expectedKey: view.expectedKey,
        expectedStartedAtMs: view.expectedStartedAtMs,
        hasExpected: view.hasExpected,
        backendState: view.visualState,
        finalKey: view.finalKey
      });
      card.classList.toggle('device-unavailable', !view.productionSupported);
      card.querySelector('.midi-return-state').textContent = view.label || (
        visual === 'confirmed' ? '✓ Boucle confirmée' :
        visual === 'mismatch' ? '⚠ Retour différent' :
        visual === 'waiting' ? 'Retour en attente…' :
        visual === 'timeout' ? '⚠ Retour absent' : ''
      );
      container.appendChild(card);
    });
    Array.from(container.children).forEach(card => {
      if (!retained.has(card.dataset.deviceId)) card.remove();
    });
    container.dataset.deviceCount = String(visible.length);
    return visible.map(deviceViewModel);
  }

  root.CLMidiReturnVisual = {createController, devicesFromState, visibleDevices, deviceViewModel, renderDeviceCards};
})(typeof window !== 'undefined' ? window : globalThis);
