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

  window.CLRemoteLTC = {
    render(element, state) {
      if (!element) return;
      const connected = Boolean(state && state.ltc_connected === true);
      const value = state && typeof state.ltc_timecode === 'string'
        ? state.ltc_timecode.trim()
        : '';
      const active = connected && LTC_PATTERN.test(value);
      element.textContent = active ? value : LTC_PLACEHOLDER;
      const display = element.closest('.ltc-display');
      if (display) {
        display.classList.toggle('ltc-display--connected', active);
        display.classList.toggle('ltc-display--disconnected', !active);
      }
    }
  };

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
  };

  if (status) new MutationObserver(syncState).observe(status, {attributes: true, childList: true, subtree: true});
  if (currentCard) new MutationObserver(syncState).observe(currentCard, {attributes: true, attributeFilter: ['class']});
  syncEnergyState();
  syncState();
})();
