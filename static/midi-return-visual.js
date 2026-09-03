(function (root) {
  'use strict';

  const FINAL_STATES = new Set(['confirmed', 'mismatch', 'timeout', 'idle']);

  const runtimeDiagnostics = {
    counters: {GO_EVENT_COUNT: 0, PROGRAM_RECALL_COUNT: 0, PROGRAM_RAF1_COUNT: 0, PROGRAM_RAF2_COUNT: 0},
    entries: []
  };

  function runtimeTrace(event, details) {
    if (event in runtimeDiagnostics.counters) runtimeDiagnostics.counters[event] += 1;
    const detailText = details && typeof details === 'object'
      ? Object.entries(details).map(([key, value]) => `${key}=${String(value)}`).join(' ')
      : String(details || '');
    runtimeDiagnostics.entries.push(`${new Date().toISOString()} ${event} ${detailText}`.trim());
    if (root.console && typeof root.console.log === 'function') {
      root.console.log('[CL_RUNTIME_ANIMATION]', event, JSON.stringify(details || {}));
    }
  }

  function computedAnimationDetails(element) {
    if (!root.getComputedStyle) return {};
    const cardStyle = root.getComputedStyle(element);
    const beforeStyle = root.getComputedStyle(element, '::before');
    const afterStyle = root.getComputedStyle(element, '::after');
    return {
      className: element.className,
      animationName: cardStyle.animationName,
      animationDuration: cardStyle.animationDuration,
      animationPlayState: cardStyle.animationPlayState,
      parentOverflow: cardStyle.overflow,
      beforeAnimationName: beforeStyle.animationName,
      beforeAnimationDuration: beforeStyle.animationDuration,
      beforeAnimationIterationCount: beforeStyle.animationIterationCount,
      beforeAnimationPlayState: beforeStyle.animationPlayState,
      beforeOpacity: beforeStyle.opacity,
      beforeBackgroundColor: beforeStyle.backgroundColor,
      beforeBackgroundImage: beforeStyle.backgroundImage,
      beforeBoxShadow: beforeStyle.boxShadow,
      beforeDisplay: beforeStyle.display,
      beforeContent: beforeStyle.content,
      beforePosition: beforeStyle.position,
      beforeInset: [beforeStyle.top, beforeStyle.right, beforeStyle.bottom, beforeStyle.left].join(' '),
      beforeWidth: beforeStyle.width,
      beforeHeight: beforeStyle.height,
      beforeZIndex: beforeStyle.zIndex,
      afterAnimationName: afterStyle.animationName,
      afterAnimationDuration: afterStyle.animationDuration,
      afterAnimationPlayState: afterStyle.animationPlayState,
      afterOpacity: afterStyle.opacity,
      afterContent: afterStyle.content,
      afterPosition: afterStyle.position,
      afterInset: [afterStyle.top, afterStyle.right, afterStyle.bottom, afterStyle.left].join(' '),
      afterWidth: afterStyle.width,
      afterHeight: afterStyle.height,
      afterZIndex: afterStyle.zIndex,
      prefersReducedMotion: Boolean(root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches),
      laterStyleSheets: root.document ? Array.from(root.document.styleSheets).map(sheet => sheet.href || 'inline') : []
    };
  }

  function schedulePostAddDiagnostics(element, eventPrefix, details) {
    [0, 50, 250, 1000, 4000].forEach(delay => {
      root.setTimeout(() => {
        runtimeTrace(`${eventPrefix}_AFTER_${delay}MS`, {
          ...details,
          ...computedAnimationDetails(element)
        });
      }, delay);
    });
  }

  function restartCssAnimation(element, className, requestFrame, shouldApply, diagnostics) {
    const generation = (element._cssAnimationGeneration || 0) + 1;
    element._cssAnimationGeneration = generation;
    if (diagnostics) runtimeTrace(diagnostics.beginEvent, {...diagnostics.details, classBefore:element.className});
    element.classList.remove(className);
    if (diagnostics) runtimeTrace(diagnostics.removeEvent, {...diagnostics.details, classAfterRemove:element.className});
    void element.offsetWidth;
    requestFrame(() => {
      if (diagnostics) runtimeTrace(diagnostics.raf1Event, diagnostics.details);
      requestFrame(() => {
        if (diagnostics) runtimeTrace(diagnostics.raf2Event, diagnostics.details);
        if (element._cssAnimationGeneration !== generation) return;
        if (shouldApply && !shouldApply()) return;
        element.classList.add(className);
        if (diagnostics) runtimeTrace(diagnostics.addEvent, {
          ...diagnostics.details,
          classAfterAdd:element.className,
          ...computedAnimationDetails(element)
        });
        if (diagnostics) schedulePostAddDiagnostics(
          element,
          diagnostics.addEvent,
          diagnostics.details
        );
      });
    });
    return generation;
  }

  function createController(options) {
    const applyState = options.applyState;
    const restartWaiting = options.restartWaiting || (() => {});
    const now = options.now || Date.now;
    const requestFrame = options.requestFrame || root.requestAnimationFrame.bind(root);
    const setTimer = options.setTimer || root.setTimeout.bind(root);
    const clearTimer = options.clearTimer || root.clearTimeout.bind(root);
    const waitingMs = options.waitingMs || 1000;
    const confirmedMs = options.confirmedMs || 2500;

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
          phase = 'loaded';
          applyState('loaded');
          return;
        }
        phase = 'confirmed';
        confirmedUntil = now() + confirmedMs;
        applyState('confirmed');
        const confirmationGeneration = generation;
        timer = setTimer(() => {
          if (generation !== confirmationGeneration || phase !== 'confirmed') return;
          completedConfirmationKey = pendingFinalKey;
          phase = 'loaded';
          applyState('loaded');
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

    const startWaiting = (expectedKey, expectedStartedAtMs, backendState, finalKey, previousExpectedKey) => {
      generation += 1;
      cancelTimer();
      lastExpectedKey = expectedKey;
      pendingFinalState = null;
      pendingFinalKey = '';
      const reportedStart = Number(expectedStartedAtMs);
      const discoveredAt = now();
      const visualStart = Number.isFinite(reportedStart) && reportedStart > 0
        ? Math.max(reportedStart, discoveredAt)
        : discoveredAt;
      waitingUntil = visualStart + waitingMs;
      confirmedUntil = 0;
      rememberFinal(backendState, finalKey);

      if (backendState === 'mismatch' || waitingUntil <= now()) {
        showFinalState();
        return;
      }
      phase = 'waiting-frame';

      // Cette affectation est synchrone : aucune réponse backend du même
      // cycle ne peut remplacer WAITING avant la première frame demandée.
      restartWaiting({previousExpectedKey, expectedKey, expectedStartedAtMs});
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
        if (hasExpected && lastExpectedKey === null) {
          // Hydratation initiale : l'EXPECTED déjà présent n'est pas un nouveau recall.
          lastExpectedKey = expectedKey;
          rememberFinal(backendState, finalKey);
          showFinalState();
          return phase;
        }

        if (hasExpected && expectedKey !== lastExpectedKey) {
          startWaiting(expectedKey, expectedStartedAtMs, backendState, finalKey, lastExpectedKey);
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

          if (backendState === 'confirmed') {
            rememberFinal(backendState, finalKey);

            // La validation métier peut être immédiate, mais le WAITING
            // visuel reste affiché jusqu'à son échéance frontend.
            if (now() >= waitingUntil) {
              generation += 1;
              cancelTimer();
              showFinalState();
              return phase;
            }
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
          waitingMs: 1000,
          confirmedMs: 2500,
          restartWaiting: diagnostic => {
            const details = {
              deviceId:view.id,
              oldExpectedKey:diagnostic.previousExpectedKey,
              newExpectedKey:diagnostic.expectedKey,
              expectedActivatedAt:device.expected_activated_at
            };
            restartCssAnimation(card, 'recall-pulse', root.requestAnimationFrame.bind(root), () => (
              card.classList.contains('state-waiting')
            ), {
              beginEvent:'PROGRAM_RECALL_COUNT',
              removeEvent:'PROGRAM_REMOVE',
              raf1Event:'PROGRAM_RAF1_COUNT',
              raf2Event:'PROGRAM_RAF2_COUNT',
              addEvent:'PROGRAM_ADD',
              details
            });

            if (typeof card.animate === 'function') {
              if (!card._globalRecallOverlay) {
                const overlay = root.document.createElement('span');
                overlay.className = 'global-recall-overlay';
                Object.assign(overlay.style, {
                  position: 'absolute',
                  inset: '0',
                  borderRadius: 'inherit',
                  pointerEvents: 'none',
                  opacity: '0',
                  zIndex: '3'
                });
                card.appendChild(overlay);
                card._globalRecallOverlay = overlay;
              }

              if (card._globalRecallAnimation) {
                card._globalRecallAnimation.cancel();
              }

              const style = root.getComputedStyle(card);
              const accent = style.getPropertyValue('--console-accent').trim() || '#7c4dff';
              const overlay = card._globalRecallOverlay;

              overlay.style.background = accent;

              card._globalRecallAnimation = overlay.animate([
                { offset: 0, opacity: 0.30 },
                { offset: 0.22, opacity: 0.70 },
                { offset: 1, opacity: 0.30 }
              ], {
                duration: 3800,
                easing: 'ease-in-out',
                iterations: 1
              });

              card._globalRecallAnimation.onfinish = () => {
                overlay.style.opacity = '0.30';
              };

              /* Sweep CENTRE -> BORDS */
              if (!card._recallSweepOverlay) {
                const sweep = root.document.createElement('span');
                sweep.className = 'recall-sweep-overlay';
                Object.assign(sweep.style, {
                  position: 'absolute',
                  left: '50%',
                  top: '50%',
                  width: '6%',
                  height: '70%',
                  borderRadius: '999px',
                  pointerEvents: 'none',
                  opacity: '0',
                  zIndex: '4',
                  transform: 'translate(-50%, -50%)'
                });
                card.appendChild(sweep);
                card._recallSweepOverlay = sweep;
              }

              const sweep = card._recallSweepOverlay;

              sweep.style.background =
                `radial-gradient(
                  ellipse,
                  white 0%,
                  ${accent} 28%,
                  color-mix(in srgb, ${accent} 28%, transparent) 58%,
                  transparent 80%
                )`;

              sweep.style.filter = 'blur(3.6px)';

              if (card._recallSweepAnimation) {
                card._recallSweepAnimation.cancel();
              }

              card._recallSweepAnimation = sweep.animate([
                {
                  transform: 'translate(-50%, -50%) scaleX(.2)',
                  opacity: 0
                },
                {
                  offset: 0.28,
                  opacity: 0.75
                },
                {
                  transform: 'translate(-50%, -50%) scaleX(11.33)',
                  opacity: 0
                }
              ], {
                duration: 1750,
                easing: 'ease-out',
                iterations: 1
              });
            }
          },
          applyState: state => {
            ['idle','waiting','confirmed','loaded','mismatch','timeout'].forEach(item => card.classList.toggle('state-' + item, state === item));

            if (state === 'waiting') {
              card.classList.add('recall-pulse');
            } else if (card.classList.contains('recall-pulse')) {
              runtimeTrace('PROGRAM_RECALL_REMOVE_BY_STATE', {
                deviceId:view.id,
                state,
                classBeforeRemove:card.className
              });
              card.classList.remove('recall-pulse');
            }
          }
        });
      }
      let visual = card._visualController.update({
        expectedKey: view.expectedKey,
        expectedStartedAtMs: view.expectedStartedAtMs,
        hasExpected: view.hasExpected,
        backendState: view.visualState,
        finalKey: view.finalKey
      });

      /*
       * STOP est uniquement un reset VISUEL.
       * On ne modifie ni EXPECTED, ni RETURNED, ni l'état métier MIDI.
       */
      if (options.forceIdle) {
        ['idle','waiting','confirmed','loaded','mismatch','timeout'].forEach(item => {
          card.classList.toggle('state-' + item, item === 'idle');
        });
        card.classList.remove('recall-pulse');

        if (card._globalRecallAnimation) {
          card._globalRecallAnimation.cancel();
        }
        if (card._globalRecallOverlay) {
          card._globalRecallOverlay.style.opacity = '0';
        }

        if (card._recallSweepAnimation) {
          card._recallSweepAnimation.cancel();
        }
        if (card._recallSweepOverlay) {
          card._recallSweepOverlay.style.opacity = '0';
        }

        visual = 'idle';
      }
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

  root.CLMidiReturnVisual = {createController, restartCssAnimation, runtimeTrace, runtimeDiagnostics, devicesFromState, visibleDevices, deviceViewModel, renderDeviceCards};
})(typeof window !== 'undefined' ? window : globalThis);
