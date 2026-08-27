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

function scenario(interfaceName, finalState = 'confirmed') {
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
    hasExpected: true,
    backendState: finalState,
    finalKey: `program-114:return-114:${interfaceName}`
  });
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: premier rendu`);

  frames.shift()();
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: première frame`);

  advanceTo(599);
  controller.update({
    expectedKey: 'program-114',
    hasExpected: true,
    backendState: finalState,
    finalKey: `program-114:return-114:${interfaceName}`
  });
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: avant 600 ms`);

  advanceTo(600);
  assert.equal(states.at(-1).state, finalState, `${interfaceName}: état final après 600 ms`);

  if (finalState === 'confirmed') {
    advanceTo(1099);
    assert.equal(states.at(-1).state, 'confirmed', `${interfaceName}: vert pendant 500 ms`);
    advanceTo(1100);
    assert.equal(states.at(-1).state, 'idle', `${interfaceName}: retour normal après 500 ms`);
  }
}

scenario('session');
scenario('arrangement');
scenario('session-mismatch', 'mismatch');
scenario('arrangement-mismatch', 'mismatch');

// Le backend peut encore annoncer "waiting" à la fin des 600 ms, puis
// publier le timeout au polling suivant. Ce timeout doit arrêter le flash.
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
  const payload = {expectedKey: 'late-timeout', hasExpected: true, backendState: 'waiting', finalKey: ''};
  controller.update(payload);
  frames.shift()();
  now = 600;
  timers.shift().callback();
  assert.equal(states.at(-1), 'waiting', 'attente conservée tant que le backend attend');
  now = 2100;
  controller.update({...payload, backendState: 'timeout'});
  assert.equal(states.at(-1), 'timeout', 'le timeout tardif arrête le flash');
}

console.log('midi-return-visual: 5 scénarios réussis');
