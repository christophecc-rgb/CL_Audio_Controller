(() => {
  const controllers = new Set();

  window.CLRemoteEnergy = {
    startPolling(task, isActive, options = {}) {
      const activeMs = Math.max(250, Number(options.activeMs) || 900);
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
        wake() { schedule(document.hidden ? hiddenMs : 40); },
        stop() {
          stopped = true;
          clearTimeout(timer);
          controllers.delete(controller);
        }
      };
      controllers.add(controller);
      schedule();
      return controller;
    }
  };

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
