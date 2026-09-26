(() => {
  const controllers = new Set();

  window.CLRemoteEnergy = {
    startPolling(task, isActive, options = {}) {
      const minActiveMs = Math.max(40, Number(options.minActiveMs) || 250);
      const activeMs = Math.max(minActiveMs, Number(options.activeMs) || 900);
      const idleMs = Math.max(activeMs, Number(options.idleMs) || 2500);
      const hiddenMs = Math.max(idleMs, Number(options.hiddenMs) || 15000);
      let timer = null;
      let running = false;
      let stopped = false;

      const delay = () => document.hidden
        ? hiddenMs
        : (typeof isActive === 'function' && isActive() ? activeMs : idleMs);

      const schedule = (overrideDelay) => {
        if (stopped) return;
        clearTimeout(timer);
        timer = setTimeout(tick, typeof overrideDelay === 'number' ? overrideDelay : delay());
      };

      const tick = async () => {
        if (stopped) return;
        if (running) {
          schedule();
          return;
        }
        running = true;
        try { await task(); }
        catch (_) {}
        finally {
          running = false;
          schedule();
        }
      };

      const controller = {
        wake() { schedule(document.hidden ? hiddenMs : 0); },
        stop() {
          stopped = true;
          clearTimeout(timer);
          controllers.delete(controller);
        }
      };
      controllers.add(controller);
      schedule(0);
      return controller;
    }
  };

  const LTC_PLACEHOLDER = '--:--:--:--';
  const LTC_PATTERN = /^\d{2}:\d{2}:\d{2}:\d{2}$/;
  const ltcClocks = new WeakMap();

  const parseLtcFrames = (value, fps) => {
    const parts = value.split(':').map(Number);
    return (((parts[0] * 60 + parts[1]) * 60 + parts[2]) * fps) + parts[3];
  };

  const formatLtcFrames = (frames, fps) => {
    const dayFrames = 24 * 60 * 60 * fps;
    let value = ((frames % dayFrames) + dayFrames) % dayFrames;
    const ff = value % fps;
    value = Math.floor(value / fps);
    const ss = value % 60;
    value = Math.floor(value / 60);
    const mm = value % 60;
    const hh = Math.floor(value / 60) % 24;
    return [hh, mm, ss, ff].map(part => String(part).padStart(2, '0')).join(':');
  };

  window.CLRemoteLTC = {
    enableSmoothing(element, fps = 25) {
      if (!element || ltcClocks.has(element)) return;
      const clock = { baseFrames: null, fps, syncedAt: 0, playing: false };
      ltcClocks.set(element, clock);
      window.setInterval(() => {
        if (clock.baseFrames === null || !clock.playing || document.hidden) return;
        const elapsedFrames = Math.floor((performance.now() - clock.syncedAt) * clock.fps / 1000);
        element.textContent = formatLtcFrames(clock.baseFrames + elapsedFrames, clock.fps);
      }, Math.round(1000 / fps));
    },
    setPlaying(element, playing) {
      const clock = ltcClocks.get(element);
      if (!clock) return;
      if (clock.playing === Boolean(playing)) return;
      if (clock.playing && !playing && clock.baseFrames !== null) {
        const elapsedFrames = Math.floor((performance.now() - clock.syncedAt) * clock.fps / 1000);
        clock.baseFrames += elapsedFrames;
        clock.syncedAt = performance.now();
        element.textContent = formatLtcFrames(clock.baseFrames, clock.fps);
      } else if (!clock.playing && playing) {
        const current = (element.textContent || '').trim();
        if (LTC_PATTERN.test(current)) {
          clock.baseFrames = parseLtcFrames(current, clock.fps);
          clock.syncedAt = performance.now();
        }
      }
      clock.playing = Boolean(playing);
    },
    render(element, state) {
      if (!element) return;
      const connected = Boolean(state && state.ltc_connected === true);
      const value = state && typeof state.ltc_timecode === 'string'
        ? state.ltc_timecode.trim()
        : '';
      const active = connected && LTC_PATTERN.test(value);
      element.textContent = active ? value : LTC_PLACEHOLDER;
      const clock = ltcClocks.get(element);
      if (clock) {
        clock.baseFrames = active ? parseLtcFrames(value, clock.fps) : null;
        clock.syncedAt = performance.now();
      }
      const display = element.closest('.ltc-display');
      if (display) {
        display.classList.toggle('ltc-display--connected', active);
        display.classList.toggle('ltc-display--disconnected', !active);
      }
    }
  };

  const sharedLtcTimecode = document.getElementById('ltcTimecode');
  if (sharedLtcTimecode) window.CLRemoteLTC.enableSmoothing(sharedLtcTimecode, 25);

  const arrangementWarning = 'Attention : vous passez en mode Arrangement. Cette action peut modifier la lecture en cours. Continuer ?';
  document.querySelectorAll('[data-arrangement-link]').forEach(link => {
    link.addEventListener('click', async event => {
      event.preventDefault();
      if (!window.confirm(arrangementWarning)) return;
      try {
        const response = await fetch('/action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'back_to_arrangement' })
        });
        if (!response.ok) throw new Error('Activation Arrangement refusée');
        window.location.assign(link.href);
      } catch (_) {
        window.alert('Impossible d’activer le mode Arrangement.');
      }
    });
  });

  const syncEnergyState = () => {
    document.body.classList.toggle('v2-energy-saver', document.hidden);
    controllers.forEach(controller => controller.wake());
  };
  document.addEventListener('visibilitychange', syncEnergyState);
  window.addEventListener('online', () => controllers.forEach(controller => controller.wake()));

  const status = document.getElementById('status');
  const healthLabel = document.getElementById('v2HealthLabel');
  const healthDetail = document.getElementById('v2HealthDetail');
  const footerMessage = document.getElementById('v2FooterMessage');
  const currentCard = document.getElementById('currentCard') || document.getElementById('currentTitleCard') || document.querySelector('.card.current');

  const syncState = () => {
    if (!status) return;
    const text = (status.textContent || '').trim() || 'Connexion…';
    const disconnected = status.classList.contains('disconnected') || /déconnect|erreur|impossible|hors ligne/i.test(text);
    document.body.classList.toggle('v2-connected', !disconnected);
    document.body.classList.toggle('v2-error', disconnected && !/connexion/i.test(text));
    if (healthLabel) healthLabel.textContent = disconnected ? 'Hors ligne' : 'Ableton connecté';
    if (healthDetail) healthDetail.textContent = text.replace(/^●\s*/, '');
    if (footerMessage) footerMessage.textContent = text.replace(/^●\s*/, '');

    const playing = currentCard && (
      currentCard.classList.contains('is-playing') ||
      currentCard.classList.contains('playing') ||
      currentCard.classList.contains('live')
    );
    document.body.classList.toggle('v2-playing', Boolean(playing));
    if (sharedLtcTimecode) window.CLRemoteLTC.setPlaying(sharedLtcTimecode, Boolean(playing));
  };

  if (status) new MutationObserver(syncState).observe(status, {attributes: true, childList: true, subtree: true});
  if (currentCard) new MutationObserver(syncState).observe(currentCard, {attributes: true, attributeFilter: ['class']});
  syncEnergyState();
  syncState();
})();


/* CL_REMOTE_ADVANCED_TOOLS_V1
 *
 * Organisation iPhone :
 * - diagnostic OSC/réseau retiré de la zone principale ;
 * - diagnostic déplacé dans Options avancées ;
 * - menu d'accès aux applications CL ;
 * - aucune logique Ableton/MIDI/OSC n'est modifiée.
 */
(() => {
  'use strict';

  function initAdvancedTools() {
    const advanced = document.querySelector('.advanced-options');
    if (!advanced) return;

    if (advanced.dataset.clAdvancedReady === '1') return;
    advanced.dataset.clAdvancedReady = '1';

    let content = advanced.querySelector('.advanced-options__content');

    if (!content) {
      content = document.createElement('div');
      content.className = 'advanced-options__content';
      advanced.appendChild(content);
    }

    const tools = document.createElement('div');
    tools.className = 'cl-advanced-tools';

    /*
     * ----------------------------------------------------------
     * APPLICATIONS CL
     * ----------------------------------------------------------
     *
     * Toutes les URL sont relatives :
     * si le Mac change de 192.168.x.x à une autre IP,
     * les liens continuent de fonctionner.
     */
    const appSection = document.createElement('section');
    appSection.className = 'cl-advanced-section';

    const appTitle = document.createElement('div');
    appTitle.className = 'cl-advanced-title';
    appTitle.textContent = 'Applications CL';

    const launcher = document.createElement('div');
    launcher.className = 'cl-app-launcher';

    const select = document.createElement('select');
    select.setAttribute('aria-label', 'Application CL');

    [
      ['', 'Choisir une application…'],
      ['/', 'Télécommande Session'],
      ['/ab', 'Télécommande A/B'],
      ['/arrangement', 'Arrangement'],

    ].forEach(([value, label]) => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = label;

      if (
        value &&
        window.location.pathname === value
      ) {
        option.selected = true;
      }

      select.appendChild(option);
    });

    const openButton = document.createElement('button');
    openButton.type = 'button';
    openButton.textContent = 'Ouvrir';

    const openSelected = () => {
      if (!select.value) return;
      window.location.href = select.value;
    };

    openButton.addEventListener('click', openSelected);

    select.addEventListener('change', () => {
      /*
       * Pas de navigation automatique :
       * évite de quitter l'exploitation par une fausse manipulation.
       */
    });

    launcher.append(select, openButton);
    appSection.append(appTitle, launcher);
    tools.append(appSection);

    /*
     * ----------------------------------------------------------
     * DIAGNOSTIC
     * ----------------------------------------------------------
     */
    const diagnosticSection = document.createElement('section');
    diagnosticSection.className = 'cl-advanced-section';

    const diagnosticTitle = document.createElement('div');
    diagnosticTitle.className = 'cl-advanced-title';
    diagnosticTitle.textContent = 'Diagnostic réseau / OSC';

    const diagnosticSlot = document.createElement('div');
    diagnosticSlot.className = 'cl-diagnostic-slot';

    diagnosticSection.append(
      diagnosticTitle,
      diagnosticSlot
    );

    tools.append(diagnosticSection);

    /*
     * Le compteur existant garde son ID et donc tous ses handlers JS.
     * On ne le recrée pas : on déplace simplement son nœud DOM.
     */
    const oscMeter = document.getElementById('oscMeter');

    if (oscMeter) {
      diagnosticSlot.appendChild(oscMeter);
    } else {
      diagnosticSlot.textContent =
        'Diagnostic OSC indisponible sur cette vue.';
    }

    content.prepend(tools);

    /*
     * Si le compteur est ajouté un peu plus tard par un autre script,
     * on le récupère sans polling permanent.
     */
    if (!oscMeter) {
      const observer = new MutationObserver(() => {
        const meter = document.getElementById('oscMeter');

        if (!meter) return;

        diagnosticSlot.replaceChildren(meter);
        observer.disconnect();
      });

      observer.observe(document.body, {
        childList: true,
        subtree: true
      });

      window.setTimeout(
        () => observer.disconnect(),
        5000
      );
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener(
      'DOMContentLoaded',
      initAdvancedTools,
      {once:true}
    );
  } else {
    initAdvancedTools();
  }
})();

/* CL_DESKTOP_REMOTE_MODE_V1 */
(() => {
  try {
    const params = new URLSearchParams(window.location.search);

    if (params.get('desktop') === '1') {
      document.documentElement.dataset.desktopRemote = '1';

      const apply = () => {
        if (document.body) {
          document.body.dataset.desktopRemote = '1';
        }
      };

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', apply, {once:true});
      } else {
        apply();
      }
    }
  } catch (_) {}
})();

/* CL_CURRENT_FLOW: Skin presentation; reads accepted UI state. */
(() => {
  const install = () => {
    const current = document.querySelector('.v2-app[data-module] .sc-current');
    if (!current) return;
    let layer = current.querySelector('.cl-current-flow-layer');
    if (!layer) {
      layer = document.createElement('div');
      layer.className = 'cl-current-flow-layer';
      layer.setAttribute('aria-hidden', 'true');
      current.prepend(layer);
    }
    const motion = matchMedia('(prefers-reduced-motion: reduce)');
    let animation, flash, previousRecall = false;
    const enabled = () => ['original','broadcast','theatre','show-control','neon','paradis-gold','paradis-silver','paradis-white'].includes(document.body.dataset.skin);
    const sync = () => {
      if (!enabled()) {
        if (animation) animation.pause();
        if (flash) flash.cancel();
        return;
      }
      if (!animation) {
        animation = layer.animate([
          {transform:'translate3d(-12%,0,0) scaleX(.96)'},
          {transform:'translate3d(12%,0,0) scaleX(1.04)'}
        ], {
          duration:9000,
          iterations:Infinity,
          direction:'alternate',
          easing:'ease-in-out'
        });
        animation.pause();
        animation.currentTime = 2600;
        layer._clFlowAnimation = animation;
      }
      const state = current.dataset.uiState;
      const preference = document.body.dataset.visualAnimation;
      const speed = preference === 'soft' ? 0.5 : 1;
      if (animation.playbackRate !== speed) animation.updatePlaybackRate(speed);
      if (state === 'playing' && preference !== 'off' && !document.hidden && !motion.matches &&
          !document.body.classList.contains('v2-energy-saver')) animation.play();
      else animation.pause();
      // Pause never seeks: resume uses the same Animation and currentTime.
      if (state === 'stopped' || state === 'offline' || !state) animation.currentTime = 2600;
      const recalled = current.classList.contains('session-recall-pulse');
      if (recalled && !previousRecall) pulse();
      previousRecall = recalled;
      if (state === 'offline' && flash) flash.cancel();
    };
    const pulse = () => {
      if (!enabled() || current.dataset.uiState === 'offline') return;
      if (flash) flash.cancel();
      // Independent one-shot flash never restarts or seeks the moving layer.
      flash = layer.animate([{filter:'brightness(1)'},{filter:'brightness(2.8)',offset:.18},{filter:'brightness(1)'}],
        {duration:motion.matches ? 180 : 850,easing:'ease-out'});
    };
    new MutationObserver(sync).observe(current,{attributes:true,attributeFilter:['data-ui-state','class']});
    new MutationObserver(sync).observe(document.body,{attributes:true,attributeFilter:['data-skin','class','data-visual-animation']});
    document.addEventListener('visibilitychange',sync);
    motion.addEventListener('change',sync);
    const go = document.querySelector('.go-button, #abSceneConfirm, #goBtn');
    if (go) go.addEventListener('click',()=>{if(!go.disabled)pulse();});
    document.addEventListener('keydown',event=>{
      if(event.key==='Enter' && event.defaultPrevented && !event.repeat &&
         !event.target.closest('input,select,textarea,[contenteditable="true"]')) pulse();
    });
    sync();
  };
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',install,{once:true});
  else install();
})();
