# Kit CL pour Intel et Apple Silicon

Le script `scripts/export_transport_kit.command` produit par défaut Universal 2.
Les cinq applications Python, les outils MIDI et les interfaces d’installation
embarquent x86_64 et arm64. La suite complète requiert macOS 12 minimum : les
deux tranches du FFmpeg fourni déclarent 12.0. Les quatre applications Python
CL déclarent explicitement leur minimum (11.0, sauf Show Audio Builder : 12.0).

## Construction

Utiliser un Python framework Universal 2, avec Tk et PyObjC pour les deux
architectures, puis installer `requirements.txt`. `CL_PYTHON` permet de choisir
l’interpréteur. Pillow sert seulement à générer les icônes ; il est exclu des
applications, qui n’utilisent pas le traitement d’images PDF. MarkupSafe utilise
son implémentation Python à la place de l’accélérateur facultatif.

Conserver les dépôts voisins `AbletonOSC` et `CL_Arrangement_Builder_Live` :
le second fournit son propre spec Universal 2. Les sources non commitées sont
incluses pour les applications ; AbletonOSC est exporté depuis son commit Git.
Le FFmpeg Universal 2 doit être présent dans `vendor/ffmpeg/macos/ffmpeg`.

Exemple, depuis la racine du dépôt :

```sh
CL_BUILD_ARCH=universal2 CL_SUITE_SKIP_ICLOUD=1 CL_SUITE_REVEAL_OUTPUT=0 \
  CL_SUITE_EXPORT_DIR=/chemin/vers/export \
  bash scripts/export_transport_kit.command
```

Les cibles `x86_64` et `arm64` sont également acceptées pour les applications
CL ; les utilitaires natifs et Arrangement Builder restent universels. Seule
la construction complète Universal 2 a été validée lors de cet audit.

Le contrôle récursif `scripts/verify_macos_architectures.py` refuse un kit dès
qu’un Mach-O manque une architecture demandée. Il vérifie également les
bibliothèques imbriquées, et produit `ARCHITECTURES.json` dans le kit. Cette
vérification ne remplace pas un lancement sur la version macOS cible.
Le ZIP est contrôlé avant sa copie vers la destination d’export.

## Validation sans modifier les installations

Construire dans une copie des trois sources pour préserver aussi les icônes
régénérées par les scripts de build. Utiliser une destination temporaire et
`CL_SUITE_SKIP_ICLOUD=1`, puis vérifier les SHA-256 et signatures.
Pour tester le moteur d’installation, définir `CL_SUITE_INSTALL_HOME` sur un
répertoire temporaire, `CL_SUITE_NONINTERACTIVE=1`, un faux Live via
`CL_SUITE_LIVE_APPS` et `CL_SUITE_ASSUME_M4L=1`. L’agent RTP n’est lancé que
pour le véritable dossier utilisateur, sauf `CL_SUITE_SKIP_POSTINSTALL=1`.

## Validation matérielle restante

Sur un vrai Mac Intel avec macOS 12 ou ultérieur : ouverture Finder/Gatekeeper,
installation et lancement de chaque interface, exports WAV/MP3 avec Ableton,
OSC, MIDI/RTP et démarrage des LaunchAgents après reconnexion. Les tests x86_64
sous Rosetta ne prouvent pas ces interactions matérielles. Ableton Live et
Max for Live restent des prérequis externes. Signature ad hoc, sans notarisation.
