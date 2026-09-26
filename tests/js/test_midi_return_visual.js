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
const {restartCssAnimation, visibleDevices, deviceViewModel, devicesFromState} = context.globalThis.CLMidiReturnVisual;

// Le restart CSS réel sépare retrait et réajout sur deux frames et invalide
// un ancien callback lorsqu'un second EXPECTED arrive rapidement.
{
  const classes = new Set(['state-waiting', 'recall-pulse']);
  const frames = [];
  const element = {
    offsetWidth: 120,
    classList: {
      add: value => classes.add(value),
      remove: value => classes.delete(value),
      contains: value => classes.has(value)
    }
  };
  const requestFrame = callback => frames.push(callback);
  restartCssAnimation(element, 'recall-pulse', requestFrame, () => classes.has('state-waiting'));
  assert.equal(classes.has('recall-pulse'), false, 'restart CSS : classe retirée pendant le cycle courant');
  frames.shift()();
  assert.equal(classes.has('recall-pulse'), false, 'restart CSS : classe encore absente après la première frame');
  restartCssAnimation(element, 'recall-pulse', requestFrame, () => classes.has('state-waiting'));
  frames.shift()(); // seconde frame devenue obsolète du premier restart
  assert.equal(classes.has('recall-pulse'), false, 'restart CSS : ancien callback A invalidé');
  frames.shift()(); // première frame du restart B
  frames.shift()(); // seconde frame du restart B
  assert.equal(classes.has('recall-pulse'), true, 'restart CSS : classe réajoutée après deux frames');
}

function scenario(interfaceName) {
  let now = 0;
  let nextTimerId = 1;
  const frames = [];
  const timers = new Map();
  const states = [];
  let waitingRestarts = 0;
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: (callback, delay) => {
      const id = nextTimerId++;
      timers.set(id, {at: now + delay, callback});
      return id;
    },
    clearTimer: id => timers.delete(id),
    restartWaiting: () => { waitingRestarts += 1; },
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
    expectedKey: 'program-113',
    expectedStartedAtMs: 0,
    hasExpected: true,
    backendState: 'idle',
    finalKey: `program-113:return-113:${interfaceName}`
  });
  assert.equal(states.at(-1).state, 'idle', `${interfaceName}: hydratation initiale silencieuse`);
  assert.equal(frames.length, 0, `${interfaceName}: aucune frame au chargement`);
  assert.equal(waitingRestarts, 0, `${interfaceName}: aucun faux recall au chargement`);

  controller.update({
    expectedKey: 'program-114',
    expectedStartedAtMs: 0,
    hasExpected: true,
    backendState: 'waiting',
    finalKey: `program-114:return-114:${interfaceName}`
  });
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: nouveau recall visible`);
  assert.equal(waitingRestarts, 1, `${interfaceName}: le second EXPECTED déclenche le recall réel`);

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
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: animation minimale maintenue après confirmation rapide`);

  advanceTo(999);
  assert.equal(states.at(-1).state, 'waiting', `${interfaceName}: animation encore active avant 1 s`);
  advanceTo(1000);
  assert.equal(states.at(-1).state, 'confirmed', `${interfaceName}: confirmation fixe après 1 s minimum`);
  advanceTo(3499);
  assert.equal(states.at(-1).state, 'confirmed', `${interfaceName}: confirmation fixe pendant 2,5 s`);
  advanceTo(3500);
  // 44e999f introduced the persistent loaded phase after confirmation.
  assert.equal(states.at(-1).state, 'loaded', `${interfaceName}: confirmation mémorisée après le pulse`);
  controller.update({expectedKey:'program-114', hasExpected:true, backendState:'confirmed', finalKey:`program-114:return-114:${interfaceName}`});
  assert.equal(states.at(-1).state, 'loaded', `${interfaceName}: un statut identique ne relance pas le pulse`);
}

scenario('session');
scenario('arrangement');

// Une attente métier réelle peut dépasser le minimum visuel, puis se termine
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
  controller.update({
    expectedKey: 'before-late-return',
    expectedStartedAtMs: 0,
    hasExpected: true,
    backendState: 'idle',
    finalKey: 'before-late-return'
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
  controller.update({
    expectedKey: `before-mismatch-${interfaceName}`,
    expectedStartedAtMs: 0,
    hasExpected: true,
    backendState: 'idle',
    finalKey: `before-mismatch-${interfaceName}`
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
  let waitingRestarts = 0;
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: (callback, delay) => { timers.push({at: now + delay, callback}); return timers.length; },
    clearTimer: () => {}, // simule un ancien callback déjà en file d'attente
    restartWaiting: () => { waitingRestarts += 1; },
    applyState: state => states.push({at: now, state})
  });
  controller.update({
    expectedKey:`before-${label}`,
    expectedStartedAtMs:0,
    hasExpected:true,
    backendState:'idle',
    finalKey:`before-${label}`
  });
  controller.update({expectedKey:firstKey, expectedStartedAtMs:0, hasExpected:true, backendState:'confirmed', finalKey:firstKey});
  frames.shift()();
  const obsoleteTimer = timers[0].callback;
  now = 1000;
  controller.update({expectedKey:secondKey, expectedStartedAtMs:1000, hasExpected:true, backendState:'confirmed', finalKey:secondKey});
  assert.equal(waitingRestarts, 2, `${label}: le nouveau rappel redémarre le pulse`);
  frames.shift()();
  now = 4000;
  obsoleteTimer();
  assert.equal(states.at(-1).state, 'waiting', `${label}: ancien timer sans effet sur le nouvel état`);
  now = 4900;
  controller.update({expectedKey:secondKey, expectedStartedAtMs:1000, hasExpected:true, backendState:'confirmed', finalKey:secondKey});
  assert.equal(states.at(-1).state, 'confirmed', `${label}: nouvelle activation confirmée immédiatement`);
}

// Un bon retour à 3 s interrompt immédiatement l'attente visuelle,
// reste confirmé 2,5 s, puis revient au repos.
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
  controller.update({
    expectedKey:'before-return-at-3s',
    expectedStartedAtMs:0,
    hasExpected:true,
    backendState:'idle',
    finalKey:'before-return-at-3s'
  });
  const payload = {expectedKey:'return-at-3s', expectedStartedAtMs:0, hasExpected:true, backendState:'waiting', finalKey:''};
  controller.update(payload); frames.shift()();
  now = 3000;
  controller.update({...payload, backendState:'confirmed', finalKey:'return-at-3s:confirmed'});
  assert.equal(states.at(-1), 'confirmed', 'retour à 3 s : confirmation immédiate');
  now = 5499;
  timers.filter(timer => timer.at <= now).forEach(timer => timer.callback());
  assert.equal(states.at(-1), 'confirmed', 'retour à 3 s : confirmation encore fixe à 2,499 s');
  now = 5500;
  timers.filter(timer => timer.at <= now).forEach(timer => timer.callback());
  assert.equal(states.at(-1), 'loaded', 'retour à 3 s : confirmation mémorisée après 2,5 s');
}

// Un état backend stale ne neutralise pas un nouvel EXPECTED : la nouvelle
// activation redémarre le rappel et reste visuellement waiting.
{
  let now = 10000;
  const frames = [];
  const states = [];
  let waitingRestarts = 0;
  const controller = createController({
    now: () => now,
    requestFrame: callback => frames.push(callback),
    setTimer: () => 1,
    clearTimer: () => {},
    restartWaiting: () => { waitingRestarts += 1; },
    applyState: state => states.push(state)
  });
  controller.update({
    expectedKey:'console_a:10:9',
    expectedStartedAtMs:9000,
    hasExpected:true,
    backendState:'idle',
    finalKey:'console_a:10:9'
  });
  controller.update({expectedKey:'console_a:11:10', expectedStartedAtMs:10000, hasExpected:true, backendState:'stale', finalKey:''});
  assert.equal(states.at(-1), 'waiting', 'stale + nouvel EXPECTED : recall immédiat');
  assert.equal(waitingRestarts, 1, 'stale + nouvel EXPECTED : premier pulse');
  frames.shift()();
  now = 11000;
  controller.update({expectedKey:'console_a:11:11', expectedStartedAtMs:11000, hasExpected:true, backendState:'stale', finalKey:''});
  assert.equal(states.at(-1), 'waiting', 'même mémoire + nouveau timestamp : recall maintenu');
  assert.equal(waitingRestarts, 2, 'même mémoire + nouveau timestamp : pulse redémarré');
  now = 11500;
  controller.update({expectedKey:'console_a:12:11.5', expectedStartedAtMs:11500, hasExpected:true, backendState:'stale', finalKey:''});
  assert.equal(states.at(-1), 'waiting', 'changement rapide A vers B : nouveau recall');
  assert.equal(waitingRestarts, 3, 'changement rapide A vers B : nouvelle animation');
}

const makeDevice = (index, changes = {}) => ({
  id: index === 1 ? 'console_a' : index === 2 ? 'console_b' : `device_${index}`,
  legacy_key: index === 1 ? 'cl5' : index === 2 ? 'ql1' : null,
  display_name: `DEVICE ${index}`,
  enabled: true,
  library: index <= 2 ? (index === 1 ? 'cl5' : 'ql1') : null,
  midi_channel: index,
  production_supported: index <= 2,
  palette: {base:'#FFB067', accent:'#D7782D'},
  visibility: {show_control:true, remote:true, network_manager:true},
  ...changes
});

for (const count of [1, 2, 3, 4, 6, 8]) {
  const devices = Array.from({length:count}, (_, index) => makeDevice(index + 1));
  assert.equal(visibleDevices(devices, 'remote').length, count, `${count} devices rendus dans l'ordre`);
  assert.deepEqual(
    Array.from(visibleDevices(devices, 'remote'), device => device.id),
    Array.from(devices, device => device.id),
    `${count} devices: ordering stable`
  );
}

{
  const devices = [
    makeDevice(1),
    makeDevice(2, {display_name:'DM7', enabled:false}),
    makeDevice(3, {visibility:{show_control:true,remote:false,network_manager:true}}),
    makeDevice(4, {display_name:'LIGHTING GRANDMA BACKUP'})
  ];
  assert.deepEqual(Array.from(visibleDevices(devices, 'remote'), item => item.id), ['console_a','device_4']);
  assert.deepEqual(Array.from(visibleDevices(devices, 'show_control'), item => item.id), ['console_a','device_3','device_4']);
  const longName = deviceViewModel(devices[3]);
  assert.equal(longName.displayName, 'LIGHTING GRANDMA BACKUP');
  assert.equal(longName.label, 'Non actif en production');
  assert.equal(longName.status, 'unavailable');
  assert.equal(longName.memory, '—');
  assert.equal(longName.title, '');
  assert.equal(longName.base, '#FFB067');
}

{
  const fallback = devicesFromState({midi_console:{cl5:{validation_status:'confirmed'},ql1:{validation_status:'waiting'}}});
  assert.equal(fallback[0].display_name, 'CL5');
  assert.equal(fallback[1].display_name, 'QL1');
  assert.equal(fallback[1].midi_channel, 2);
}

console.log('midi-return-visual: 10 scénarios recall/DOM + renderer dynamique 1/2/3/4/6/8 réussis');
