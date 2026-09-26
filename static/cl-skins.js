(() => {
  'use strict';

  const STORAGE_KEY = 'cl-audio-remote-skin';

  const skins = [
    ['skin-broadcast', 'Broadcast'],
    ['skin-regie',     'Régie propre'],
    ['skin-vivid',     'Vivid'],
    ['skin-pastel',    'Pastel'],
    ['skin-outline',   'Outline'],
    ['skin-dark',      'Sombre']
  ];

  function applySkin(name) {
    const valid = skins.some(([id]) => id === name);
    const selected = valid ? name : 'skin-broadcast';

    document.documentElement.dataset.clSkin = selected;

    try {
      localStorage.setItem(STORAGE_KEY, selected);
    } catch (_) {}

    document.querySelectorAll('[data-cl-skin-selector]').forEach(select => {
      if (select.value !== selected) select.value = selected;
    });
  }

  function classifyControls() {
    document.querySelectorAll('button').forEach(button => {
      const text = String(button.textContent || '')
        .replace(/\s+/g, ' ')
        .trim()
        .toUpperCase();

      const action = String(button.dataset.action || '').toLowerCase();
      const id = String(button.id || '').toLowerCase();

      if (
        text === 'GO' ||
        text.startsWith('GO ') ||
        action.includes('go')
      ) {
        button.classList.add('cl-skin-go');
      }

      if (
        text.includes('PREVIEW') ||
        text === 'PREV' ||
        text.includes('NEXT') ||
        action.includes('prev') ||
        action.includes('next')
      ) {
        button.classList.add('cl-skin-prevnext');
      }

      if (
        action === 'play' ||
        action.includes('play') ||
        id.includes('play')
      ) {
        button.classList.add('cl-skin-play');
      }

      if (
        text.includes('PAUSE') ||
        action.includes('pause') ||
        action.includes('toggle') ||
        id.includes('pause')
      ) {
        button.classList.add('cl-skin-pause');
      }

      if (
        text === 'STOP' ||
        text.includes(' STOP') ||
        action === 'stop' ||
        action.includes('stop') ||
        id.includes('stop')
      ) {
        button.classList.add('cl-skin-stop');
      }
    });

    document.querySelectorAll('.midi-return').forEach(card => {
      const id = String(card.id || '').toLowerCase();
      const txt = String(card.textContent || '').toLowerCase();

      if (id.includes('cl5') || txt.includes('cl5')) {
        card.classList.add('cl-skin-cl5');
      }

      if (id.includes('ql1') || txt.includes('ql1')) {
        card.classList.add('cl-skin-ql1');
      }
    });
  }

  function createSkinSelector() {
    // All remote views share the four global presentation skins.
    if (document.querySelector('.v2-app[data-module]')) return;
    if (document.querySelector('[data-cl-skin-selector]')) return;

    const details =
      [...document.querySelectorAll('details')]
        .find(el => /options avanc/i.test(el.textContent || '')) ||
      document.querySelector('details');

    if (!details) return;

    const box = document.createElement('div');
    box.className = 'cl-skin-settings';

    const title = document.createElement('div');
    title.className = 'cl-skin-settings-title';
    title.textContent = 'APPARENCE';

    const row = document.createElement('div');
    row.className = 'cl-skin-settings-row';

    const label = document.createElement('label');
    label.textContent = 'Skin';

    const select = document.createElement('select');
    select.dataset.clSkinSelector = '1';

    skins.forEach(([id, labelText]) => {
      const option = document.createElement('option');
      option.value = id;
      option.textContent = labelText;
      select.appendChild(option);
    });

    select.addEventListener('change', () => {
      applySkin(select.value);
    });

    row.append(label, select);
    box.append(title, row);

    const summary = Array.from(details.children)
      .find(child => child.tagName === 'SUMMARY');

    if (summary && summary.nextSibling) {
      details.insertBefore(box, summary.nextSibling);
    } else if (summary) {
      details.appendChild(box);
    } else {
      details.insertBefore(box, details.firstChild);
    }

    const current =
      document.documentElement.dataset.clSkin ||
      'skin-broadcast';

    select.value = current;
  }

  function boot() {
    let saved = 'skin-broadcast';

    try {
      saved = localStorage.getItem(STORAGE_KEY) || saved;
    } catch (_) {}

    if (document.querySelector('.v2-app[data-module]')) {
      // Stable reference palette; do not overwrite the legacy preference.
      document.documentElement.dataset.clSkin = 'skin-broadcast';
    } else {
      applySkin(saved);
    }
    classifyControls();
    createSkinSelector();

    const observer = new MutationObserver(() => {
      classifyControls();
      createSkinSelector();
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();


/* =========================================================
   CL AUDIO — OPTIONS COMPACTES + ONDE LIVE
   ========================================================= */

(() => {
  'use strict';

  function normalizeText(element) {
    return String(element?.textContent || '')
      .replace(/\s+/g, ' ')
      .trim()
      .toLowerCase();
  }


  function compactAdvancedOptions() {
    document.querySelectorAll('details').forEach(details => {
      const txt = normalizeText(details);

      if (!txt.includes('options avanc')) return;

      /*
       * Force APPARENCE juste après le summary.
       */
      const skin = details.querySelector('.cl-skin-settings');
      const summary = Array.from(details.children)
        .find(el => el.tagName === 'SUMMARY');

      if (skin && summary && summary.nextElementSibling !== skin) {
        summary.insertAdjacentElement('afterend', skin);
      }


      /*
       * Identifie les boutons existants sans modifier leur logique.
       */
      details.querySelectorAll('button').forEach(button => {
        const text = normalizeText(button);

        if (
          text.includes('choisir/importer') ||
          text === 'importer' ||
          text === 'importer…'
        ) {
          button.classList.add('cl-library-import');
        }

        if (
          text.includes('révéler dans le finder') ||
          text.includes('reveler dans le finder') ||
          text === 'finder'
        ) {
          button.classList.add('cl-library-finder');
        }
      });


      /*
       * Input file Yamaha : on conserve totalement le comportement,
       * on ne fait que réduire son empreinte visuelle.
       */
      details.querySelectorAll('input[type="file"]').forEach(input => {
        input.classList.add('cl-library-file-input');
      });


      /*
       * Repère visuellement la zone bibliothèques.
       */
      Array.from(details.querySelectorAll('*')).forEach(element => {
        if (normalizeText(element) === 'bibliothèques de titres consoles') {
          element.parentElement?.classList.add('cl-library-compact-zone');
        }
      });
    });
  }

function refreshEnhancements() {
    compactAdvancedOptions();
  }


  function bootEnhancements() {
    refreshEnhancements();

    const observer = new MutationObserver(() => {
      refreshEnhancements();
    });

    observer.observe(document.body, {
      childList:true,
      subtree:true
    });
  }


  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootEnhancements);
  } else {
    bootEnhancements();
  }
})();
