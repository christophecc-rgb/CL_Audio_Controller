# Nettoyage prudent du 14 octobre 2026

Branche vérifiée : `feature/local-light`. L'état initial comprend 39 fichiers
suivis modifiés et de nombreuses sources non suivies : ce sont des travaux en
cours, pas des déchets. Aucun reset, commit, push ni changement de logique
MIDI/Program Change ou de CSV/CLF/RTP de production durant cette intervention.

## Cartographie vérifiée

```text
launcher_light.py (CL_APP_MODE=LOCAL_LIGHT)
  -> runtime_startup.run_light_entry()
     -> common_light_runtime.run_light() [par défaut]
        -> create_common_light_app() -> load_common_host()
           -> code de app.py chargé dans un module hôte isolé
              avec common_light_capabilities() via ContextVar
           -> CommonLightRuntime
              -> GoContext + ProfileGoConsumer (définis dans go_core.py/app.py)
              -> runtime_startup.create_common_light_controller()
                 -> ableton_runtime.CommonLightController
                    -> AbletonRuntime, SceneTimingAPI, execute_go_core
           -> templates/light.html -> static/light.css, static/light.js
           -> sécurité HTTP/remote de l'hôte et security_http.start_remote_tls

runtime_startup [CL_LIGHT_ENGINE=legacy, en développement]
  -> light_runtime.create_light_app()/run_light()
     -> app_mode (capacités/projection), go_core (GO), osc_transport
     -> light_timing.reference_candidates()/timing_from_clip()

app.py / launcher_control.py
  -> runtime_startup (sélection Light à l'exécution, garde du profil FULL)
app.py
  -> app_mode, go_core, scene_timing.SceneTimingAPI
  -> ableton_runtime.AbletonRuntime + RuntimeBindings(globals(), ...)
```

`launcher_light.py` impose le moteur commun dans une application figée.
`CL Show Control Light.spec` prend ce launcher comme entrée, inclut `app` via
`hiddenimports` et exclut `light_runtime`/`light_timing` du paquet. Le script
`scripts/build_light_kit.sh` utilise cette spec. Le secours legacy reste donc
accessible depuis les sources, même s'il n'est pas distribué.

## Décisions par fichier ou groupe

| Fichiers | Conclusion et preuve |
| --- | --- |
| `light_runtime.py`, `light_timing.py` | Historiques mais pas morts : imports conditionnels dans runtime_startup, tests directs et comparaisons ancien/nouveau. Conservés. |
| `launcher_light.py` | Entrée active du produit et de la spec. Conservé. |
| `common_light_runtime.py` | Adaptateur Light vers le moteur principal, routes HTTP, état et cycle de vie ; pas le runtime historique autonome. Conservé. |
| `ableton_runtime.py` | Suivi Ableton partagé par app.py et CommonLightController. Conservé. |
| `app_mode.py` | Capacités et projection utilisées par FULL, le profil Light commun et le secours legacy. Conservé. |
| `go_core.py` | Transactions GO utilisées par app.py, le contrôleur commun et LightRuntime. Conservé. |
| `runtime_startup.py` | Sélection de profil/moteur utilisée par les trois points d'entrée, chargement commun et secours legacy. Conservé. |
| `scene_timing.py` | Interface de timing instanciée par app.py et réutilisée par Light ; les algorithmes restent dans l'hôte. Conservé. |
| `static/light.css`, `static/light.js`, `templates/light.html` | UI active, vérifiée par tests HTTP et JavaScript. Conservée. |
| Assets d'icône et ressources remote/sécurité de la spec | Références de packaging utiles. Conservés. |
| `tests/test_common_ableton_runtime.py`, `tests/test_common_light_runtime.py`, `tests/test_local_light_go.py` | Contrats communs, profil et comparaisons ; conservés. Les comparaisons importent LightRuntime et FakeTransport de test_local_light_runtime. |
| `tests/test_local_light_runtime.py`, `tests/test_light_timing_selection.py` | Couvrent le secours encore sélectionnable ; le premier contient aussi des vérifications UI et sert aux tests de comparaison. Conservés. |
| `tests/test_light_packaging.py`, `tests/js/test_light_ui.cjs` | Packaging et UI actifs. Conservés. |
| `docs/LOCAL_LIGHT_PHASE3.md`, `docs/LOCAL_LIGHT_PHASE4.md`, `docs/LOCAL_LIGHT_TIMING.md` | Historique de migration, limites de validation et comportement legacy documenté. Pas de suppression ni réécriture de ces preuves historiques. |
| Documents RELEASE_2.3.0 et SECURITY_LIGHT_KIT_AUDIT_2026-10-09 | Qualifications et réserves utiles ; RELEASE_2.3.0.md est copié dans le kit Light. Conservés. |
| `static/marquee/*` | Les PNG sont référencés par showcue-marquee.css, mais aucun consommateur actif de cette CSS n'a été trouvé. Ancien audit demande leur conservation ; potentiel travail UI en cours. Conservés comme ambigus. |

Aucun document/test inspecté n'est démontré inutile. Aucun import applicatif
n'a été retiré : supprimer le sélecteur legacy serait un changement de
comportement et dépasserait ce nettoyage.

## Changements effectués

- Suppression de `CL Audio Controller.spec.bak_release_version` et
  `CL Show Audio Builder.spec.bak_release_version`. Fichiers ignorés/non suivis,
  motif déjà dans .gitignore, aucune référence utile trouvée. Comparaison : les
  specs actuelles contiennent tout leur contenu, plus le préambule SPECPATH.
- `tests/test_light_packaging.py` : ajout de `SPECPATH=str(ROOT)` au contexte
  d'exécution simulant PyInstaller, dans deux tests. Correction de fixtures
  dépassées, sans modifier la spec ni le code de production.
- Ajout du présent rapport. Tous les autres fichiers préexistants préservés.

## Vérification

Commande Python, avec journal de sécurité isolé dans `/private/tmp` :

```sh
CL_SECURITY_DIRECTORY=/private/tmp/cl-cleanup-security PYTHONDONTWRITEBYTECODE=1 \
.venv/bin/python -m pytest -q \
  tests/test_common_ableton_runtime.py tests/test_common_light_runtime.py \
  tests/test_local_light_go.py tests/test_local_light_runtime.py \
  tests/test_light_timing_selection.py tests/test_light_packaging.py \
  tests/test_live_set_generation.py tests/test_arrangement_go_transaction.py
node tests/js/test_light_ui.cjs
git diff --check
```

Première passe : 258 réussis, 2 échecs SPECPATH dans les fixtures de packaging,
1 ignoré et 18 sous-tests réussis. Après correction : **260 réussis, 1 ignoré,
18 sous-tests réussis**. Test JavaScript réussi ; diff --check réussi.
Pas de build ni de validation physique avec Ableton pendant cette passe.

## Décisions restantes

- Retrait futur du secours legacy seulement après décision explicite et
  validation des scénarios réels restants ; migrer alors les comparaisons et
  conserver les contrats/UI utiles avant de supprimer leurs fichiers.
- Déterminer si l'habillage marquee doit être intégré ou abandonné.
- Les docstrings de app_mode décrivent encore partiellement la phase de
  migration antérieure ; conservées ici pour limiter le périmètre. Elles ne
  doivent pas être prises comme preuve d'un runtime Light séparé par défaut.
