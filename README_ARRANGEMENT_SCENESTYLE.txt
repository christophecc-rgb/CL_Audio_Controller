Arrangement - Conduite type Mode Scène

Cette version reprend la logique du mode Session/Scènes, mais avec les Locators de la vue Arrangement :

- EN COURS : dernier repère lancé avec GO.
- PROCHAINE SCÈNE SÉLECTIONNÉE : repère prêt à partir.
- GO : saute au repère Prochaine, lance la lecture, puis prépare le repère suivant.
- PREVIEW : saute au repère Prochaine sans lancer la lecture.
- NEXT : avance uniquement la Prochaine scène sélectionnée.
- PLAY / PAUSE / STOP : transport Ableton standard.
- SCÈNE — ALLER À : choisit un locator dans la liste et le place en Prochaine scène sélectionnée.

Les repères sont lus automatiquement depuis les Locators/Cue Points du Set Ableton via AbletonOSC.
Si AbletonOSC ne renvoie pas les locators, l'application utilise arrangement_markers.json en repli.
