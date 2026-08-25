# CL Audio Configuration Checker — packaging macOS

Le bundle est reconstruit sans installation avec :

```bash
scripts/build_configuration_checker_app.sh
```

La version par défaut est `0.1.0`. Une autre version et un autre dossier de
sortie peuvent être fournis en arguments. Le script d'icône réutilise l'identité
de `assets/cl_midi_network_assistant_icon_1024.png`, remplace le sous-titre et
ajoute un badge de vérification vert distinctif. Il produit un iconset complet
puis un fichier `.icns` avec les outils macOS `sips` et `iconutil`.

Le résultat reste dans `dist/configuration-checker` et n'est jamais copié dans
`/Applications` ou `~/Applications`.
