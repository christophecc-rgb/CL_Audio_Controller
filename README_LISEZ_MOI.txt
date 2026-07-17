ABLETON WEB REMOTE PRO

Objectif : lancer une télécommande Ableton propre sans Terminal apparent.

Contenu :
- Ableton Web Remote.app : lance le serveur en arrière-plan et affiche l'adresse iPhone/iPad.
- Installer_Mac.command : installe les dépendances Python dans un environnement isolé.
- INSTALLER_AbletonOSC : installe AbletonOSC depuis la source officielle GitHub.
- Diagnostics : vérifie Python, IP, serveur, ports et présence AbletonOSC.
- Stop : arrête le serveur si besoin.
- Guides : installation rapide et note Live 10.

Ordre conseillé :
1. Installer_Mac.command
2. INSTALLER_AbletonOSC/Installer_AbletonOSC_Officiel.command
3. Redémarrer Ableton Live et choisir AbletonOSC dans les surfaces de contrôle
4. Ableton Web Remote.app

Adresse iPhone/iPad :
Une fenêtre Mac s'ouvre au lancement de l'app avec l'adresse exacte.
Elle est aussi copiée automatiquement dans le presse-papiers.

Ports :
- Web : 5050
- AbletonOSC entrée : 11000
- Retour local : 11001

Pour arrêter :
Stop/Stopper_Ableton_Web_Remote.command
