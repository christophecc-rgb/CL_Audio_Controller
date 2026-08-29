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

  root.CLMidiReturnVisual = {createController};
})(typeof window !== 'undefined' ? window : globalThis);
