const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', '..', 'static', 'midi-return-visual.js'),
  'utf8'
);
const context = {globalThis: {}};
vm.runInNewContext(source, context);
const createController = context.globalThis.CLMidiReturnVisual.createController;

function scenario(interfaceName) {
  let now = 0;
  let nextTimerId = 1;
  const frames = [];
  const timers = new Map();
  const states = [];
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: (callback, delay) => {
      const id = nextTimerId++;
      timers.set(id, {at: now + delay, callback});
      return id;
    },
    clearTimer: id => timers.delete(id),
    applyState: state => states.push({at: now, state})
  });

  const advanceTo = target => {
    now = target;
    for (;;) {
      const due = [...timers.entries()]
        .filter(([, timer]) => timer.at <= now)
        .sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      timers.delete(due[0]);
      due[1].callback();
    }
  };

  controller.update({
    expectedKey: 'program-114',
    expectedStartedAtMs: 0,
    hasExpected: true,
    backendState: 'waiting',
    finalKey: `program-114:return-114:${interfaceName}`
  });
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: premier rendu`);

  frames.shift()();
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: première frame`);

  advanceTo(200);
  controller.update({
    expectedKey: 'program-114',
    expectedStartedAtMs: 0,
    hasExpected: true,
    backendState: 'confirmed',
    finalKey: `program-114:return-114:${interfaceName}`
  });
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: confirmation métier immédiate, rappel maintenu`);

  advanceTo(1000);
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: rappel actif à 1 s`);
  advanceTo(3900);
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: rappel actif à 3,9 s`);
  advanceTo(4000);
  assert.equal(states.at(-1).state, 'confirmed', `${interfaceName}: confirmation visuelle après 4 s`);

  advanceTo(4499);
  assert.equal(states.at(-1).state, 'confirmed', `${interfaceName}: confirmation pendant 500 ms`);
  advanceTo(4500);
  assert.equal(states.at(-1).state, 'confirmed', `${interfaceName}: confirmation stable après le flash`);
}

scenario('session');
scenario('arrangement');

// Une attente métier réelle dépasse le minimum de 4 s, puis se termine
// immédiatement lorsque le bon retour arrive à 6 s.
{
  let now = 0;
  const frames = [];
  const timers = [];
  const states = [];
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: (callback, delay) => { timers.push({at: now + delay, callback}); return timers.length; },
    clearTimer: () => {},
    applyState: state => states.push(state)
  });
  const payload = {expectedKey: 'late-return', expectedStartedAtMs: 0, hasExpected: true, backendState: 'waiting', finalKey: ''};
  controller.update(payload);
  frames.shift()();
  now = 4000;
  timers.shift().callback();
  assert.equal(states.at(-1), 'waiting', 'attente conservée tant que le backend attend');
  now = 4100;
  controller.update(payload);
  assert.equal(states.at(-1), 'waiting', 'attente encore animée à 4,1 s');
  now = 6000;
  controller.update({...payload, backendState: 'confirmed', finalKey: 'late-return:confirmed'});
  assert.equal(states.at(-1), 'confirmed', 'confirmation immédiate au retour correct à 6 s');
}

// Un mismatch réel interrompt immédiatement le rappel minimum.
for (const interfaceName of ['session', 'arrangement']) {
  let now = 0;
  const frames = [];
  const timers = new Map();
  const states = [];
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: (callback, delay) => { timers.set(1, {at: now + delay, callback}); return 1; },
    clearTimer: id => timers.delete(id),
    applyState: state => states.push(state)
  });
  const payload = {expectedKey: `mismatch-${interfaceName}`, expectedStartedAtMs: 0, hasExpected: true, backendState: 'waiting', finalKey: ''};
  controller.update(payload);
  frames.shift()();
  now = 1000;
  controller.update({...payload, backendState: 'mismatch', finalKey: `${interfaceName}:wrong-return`});
  assert.equal(states.at(-1), 'mismatch', `${interfaceName}: mismatch immédiat à 1 s`);
}

// Même mémoire répétée et changement rapproché : expectedKey inclut
// l'activation canonique, et un ancien callback ne peut pas finir la nouvelle.
for (const [label, firstKey, secondKey] of [
  ['same-program', '25:activation-a', '25:activation-b'],
  ['rapid-change', '25:activation-a', '26:activation-b'],
]) {
  let now = 0;
  const frames = [];
  const timers = [];
  const states = [];
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: (callback, delay) => { timers.push({at: now + delay, callback}); return timers.length; },
    clearTimer: () => {}, // simule un ancien callback déjà en file d'attente
    applyState: state => states.push({at: now, state})
  });
  controller.update({expectedKey:firstKey, expectedStartedAtMs:0, hasExpected:true, backendState:'confirmed', finalKey:firstKey});
  frames.shift()();
  const obsoleteTimer = timers[0].callback;
  now = 1000;
  controller.update({expectedKey:secondKey, expectedStartedAtMs:1000, hasExpected:true, backendState:'confirmed', finalKey:secondKey});
  frames.shift()();
  now = 4000;
  obsoleteTimer();
  assert.equal(states.at(-1).state, 'waiting', `${label}: ancien timer sans effet`);
  now = 4900;
  controller.update({expectedKey:secondKey, expectedStartedAtMs:1000, hasExpected:true, backendState:'confirmed', finalKey:secondKey});
  assert.equal(states.at(-1).state, 'waiting', `${label}: nouveau rappel actif à 3,9 s`);
  now = 5100;
  controller.update({expectedKey:secondKey, expectedStartedAtMs:1000, hasExpected:true, backendState:'confirmed', finalKey:secondKey});
  assert.equal(states.at(-1).state, 'confirmed', `${label}: nouvelle activation confirmée après 4 s`);
}

// Un bon retour à 3 s conserve le rappel jusqu'à 4 s.
{
  let now = 0;
  const frames = [];
  const timers = [];
  const states = [];
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: (callback, delay) => { timers.push({at: now + delay, callback}); return timers.length; },
    clearTimer: () => {},
    applyState: state => states.push(state)
  });
  const payload = {expectedKey:'return-at-3s', expectedStartedAtMs:0, hasExpected:true, backendState:'waiting', finalKey:''};
  controller.update(payload); frames.shift()();
  now = 3000;
  controller.update({...payload, backendState:'confirmed', finalKey:'return-at-3s:confirmed'});
  assert.equal(states.at(-1), 'waiting', 'retour à 3 s : rappel maintenu');
  now = 3900;
  controller.update({...payload, backendState:'confirmed', finalKey:'return-at-3s:confirmed'});
  assert.equal(states.at(-1), 'waiting', 'retour à 3 s : actif à 3,9 s');
  now = 4100;
  controller.update({...payload, backendState:'confirmed', finalKey:'return-at-3s:confirmed'});
  assert.equal(states.at(-1), 'confirmed', 'retour à 3 s : stable après 4 s');
}

console.log('midi-return-visual: 8 scénarios de rappel déterministe réussis');
