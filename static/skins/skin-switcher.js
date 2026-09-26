/* Global presentation preference. No requests, transport handlers or polling. */
(() => {
  'use strict';
  const app = document.querySelector('.v2-app[data-module]');
  const advanced = app && app.querySelector('.advanced-options');
  if (!advanced || document.getElementById('sessionSkin')) return;
  const key = 'cl-audio-global-skin-v1';
  const skins = [['original', 'Original'], ['broadcast', 'Broadcast'], ['theatre', 'Theatre'], ['show-control', 'Show Control'], ['neon', 'Neon / Night'], ['paradis-gold', 'Paradis Rouge & Or'], ['paradis-silver', 'Paradis Rouge & Argent'], ['paradis-white', 'Paradis Rouge & Blanc']];
  // Additive stylesheet registration: keep functional templates and saved choices intact.
  for (const id of ['paradis-gold','paradis-silver','paradis-white']) {
    const link = document.createElement('link');
    link.rel = 'stylesheet'; link.href = '/static/skins/' + id + '.css?v=20260925-paradis';
    document.body.appendChild(link);
  }
  const valid = value => skins.some(([id]) => id === value);
  const row = document.createElement('div');
  row.className = 'session-skin-setting';
  const label = document.createElement('label');
  label.htmlFor = 'sessionSkin';
  label.textContent = 'Skin';
  const select = document.createElement('select');
  // Keep the existing selector hook for saved UI tests/accessibility.
  select.id = 'sessionSkin';
  skins.forEach(([value, text]) => select.add(new Option(text, value)));
  let saved = 'original';
  try {
    const global = localStorage.getItem(key);
    const previous = localStorage.getItem('cl-audio-session-skin-v1');
    if (valid(global)) saved = global;
    else if (global === null && valid(previous)) { saved = previous; localStorage.setItem(key, saved); }
  } catch (_) {}
  const apply = value => {
    const skin = valid(value) ? value : 'original';
    document.body.dataset.skin = skin;
    select.value = skin;
  };
  select.addEventListener('change', () => {
    apply(select.value);
    try { localStorage.setItem(key, select.value); } catch (_) {}
  });
  window.addEventListener('storage', event => {
    if (event.key === key || event.key === null) apply(event.newValue);
  });
  row.append(label, select);
  const panel = document.createElement('fieldset');
  panel.className = 'cl-visual-settings';
  const legend = document.createElement('legend'); legend.textContent = 'Apparence de la télécommande';
  panel.append(legend, row);
  const preferencesKey = 'cl-audio-visual-settings-v1';
  const definitions = [
    ['flowIntensity','Intensité du flow',[['default','Selon le skin'],['low','Faible'],['medium','Moyen'],['high','Fort']]],
    ['visualAnimation','Animation',[['normal','Normale'],['soft','Douce'],['off','Off — fixe']]],
    ['currentStyle','Scène courante',[['default','Selon le skin'],['sober','Sobre'],['halo','Halo'],['wave','Vague'],['luminous','Lumineux']]],
    ['goRelief','Relief du bouton GO',[['default','Selon le skin'],['flat','Plat'],['light','Léger relief'],['3d','3D']]]
  ];
  const controls = new Map();
  const read = () => { try { return JSON.parse(localStorage.getItem(preferencesKey)) || {}; } catch (_) { return {}; } };
  const applyPreferences = values => {
    for (const [name,,options] of definitions) {
      const value = options.some(([id])=>id===values?.[name]) ? values[name] : options[0][0];
      document.body.dataset[name] = value;
      controls.get(name).value = value;
    }
  };
  const save = () => {
    const values = Object.fromEntries([...controls].map(([key,control])=>[key,control.value]));
    applyPreferences(values);
    try { localStorage.setItem(preferencesKey,JSON.stringify(values)); } catch (_) {}
  };
  for (const [name,title,options] of definitions) {
    const wrapper = document.createElement('div'); wrapper.className='session-skin-setting';
    const caption = document.createElement('label'); caption.htmlFor='visual-'+name; caption.textContent=title;
    const control = document.createElement('select'); control.id=caption.htmlFor;
    options.forEach(([value,text])=>control.add(new Option(text,value)));
    control.addEventListener('change',save); controls.set(name,control);
    wrapper.append(caption,control); panel.append(wrapper);
  }
  const reset = document.createElement('button'); reset.type='button'; reset.className='cl-visual-reset';
  reset.textContent='Réglages du skin par défaut';
  reset.addEventListener('click',()=>{applyPreferences({});save();});
  const note = document.createElement('p'); note.textContent='Aperçu immédiat · choix mémorisés pour les trois vues';
  panel.append(reset,note);
  advanced.querySelector('summary').insertAdjacentElement('afterend', panel);
  applyPreferences(read());
  window.addEventListener('storage',event=>{
    if(event.key===preferencesKey || event.key===null) applyPreferences(read());
  });
  // Restore A/B access in the shared shell; Arrangement's existing link/handler is untouched.
  const tabs = app.querySelector('.v2-tabs');
  if (tabs && !tabs.querySelector('a[href="/ab"]')) {
    const link = document.createElement('a'); link.href = '/ab'; link.textContent = 'A/B';
    if (app.dataset.module === 'ab') link.setAttribute('aria-current', 'page');
    tabs.querySelector('a[href="/"]').insertAdjacentElement('afterend', link);
  }
  apply(saved);
})();
