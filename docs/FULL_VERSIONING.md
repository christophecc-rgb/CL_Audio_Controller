# Version du produit FULL et de ses distributions

La source unique FULL est `release_version.py` : version **2.2.0**, build **6**.
Ces valeurs restent celles du `.spec` principal, du README et du dernier
changelog publié avant normalisation. Le 2.2.1 était un défaut de l'export de kit,
sans déclaration correspondante dans le bundle principal. Les anciennes archives
ne changent pas la version déclarée des sources actuelles. Aucun numéro 2.3.0
ni module du moteur Light n'est importé dans cette branche.

## Consommateurs et catégories

| Source | Politique |
| --- | --- |
| CL Audio Controller.spec | Version/build FULL via full_version() et full_build(), imports résolus depuis SPECPATH. |
| scripts/build_release.sh | Même version pour le kit et le bundle FULL ; build dans les plists FULL générés, VERSIONS.txt et BUILD_INFO.txt. |
| scripts/export_transport_kit.command | Même version/build transmis à build_release et aux métadonnées des installateurs générés. |
| README.md | Affichage humain des valeurs par défaut, concordance contrôlée par test. |
| CHANGELOG.md | Historique des releases ; normalisation décrite dans Non publié, aucune nouvelle release déclarée. |
| CL ShowCue.spec, CL ShowCue Builder.spec, CL Show Audio Builder.spec | Versions de composants indépendantes : 1.0.0/build 1, conservées. |
| scripts/build_midi_console_package.sh | Kit MIDI indépendant, 1.0.0 par défaut. |
| scripts/build_configuration_checker_app.sh | Vérificateur indépendant, 0.1.0/build 1 par défaut. |
| scripts/install_desktop_kit_builder.sh | Outil de création de kit indépendant, 1.0.0. |
| resources/app_identity.json | Catalogue de noms/icônes/alias ; aucune version de release. |
| build_identity.py | Identité du protocole launcher/serveur, inchangée ; pas une version de produit. |
| packaging/ et manifests CL_Transport | Identités, rôles, formats et lecture des plists ; aucun changement de schéma ou de chemin de stockage. |

Les autres specs conservent leurs versions de composants. Les wrappers natifs
construits par la distribution FULL utilisent déjà la version du kit et reçoivent
maintenant son build aussi. Les bundles archivés ne sont pas réécrits.
Les noms d'applications, bundle identifiers, installateurs et protocoles ne changent pas.

## Construction

```sh
.venv/bin/python release_version.py
.venv/bin/python release_version.py --build
./scripts/build_release.sh
```

CL_AUDIO_VERSION et CL_BUILD_NUMBER permettent une surcharge explicite et
validée de distribution. Le premier argument historique de build_release.sh
reste prioritaire pour la version. Les valeurs choisies sont exportées avant
PyInstaller et propagées au chemin d'export de kit. Une version doit avoir trois
composants numériques ; un build doit en avoir un à trois. Une valeur invalide
arrête le script avant mktemp ou toute construction.

Une surcharge n'est pas une décision de publication : les valeurs par défaut
de release_version.py restent l'autorité pour les sources. Les versions des
composants indépendants ne suivent pas ces surcharges.

## Contrôles

tests/test_release_version.py exécute les specs avec factories PyInstaller
simulées, la CLI et les préambules shell avant toute opération de build. Il
contrôle valeur par défaut, surcharge cohérente, répertoire courant distinct,
rejet des entrées invalides, affichage README et indépendance des composants.
tests/test_packaging.py et le contexte du test de packaging MTC sont adaptés
sans changement de logique MIDI. Aucun build réel n'est lancé par ces tests.
