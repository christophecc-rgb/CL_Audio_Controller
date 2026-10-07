# Import Builder : format tolérant, données strictes

Les fonctions `import_csv` et `import_xlsx` conservent leur retour historique
`(document, colonnes_inconnues)`. Un dictionnaire de diagnostic optionnel reçoit
le format, l’encodage, les feuilles trouvées, la feuille retenue, les lignes
physiques, les en-têtes originaux/reconnus/manquants/inconnus et les erreurs.
La route de prévisualisation expose ce diagnostic, y compris en HTTP 400.

## Détection

- CSV : UTF-8 avec/sans BOM, UTF-16 avec BOM ou ordre des octets identifiable,
  repli Windows-1252 explicitement signalé comme présumé ; `;`, `,`, tabulation,
  `|`, directive Excel `sep=`, cellules citées et multilignes.
- XLSX : noms de feuilles libres, lignes d’en-têtes décalées, sharedStrings,
  inlineStr, chaînes riches, cellules numériques/booléennes et résultats de
  formules enregistrés, chemins OOXML absolus/relatifs, namespaces stricts
  et transitionnels. Les noms de colonnes des tableaux OOXML explicites sont
  utilisés si les cellules d’en-têtes sont absentes ; une contradiction bloque.
- Détection des colonnes insensible à la casse, aux accents, au BOM, aux espaces
  invisibles et à la ponctuation. Les données métier ne sont pas réécrites par
  cette détection. PHASE et SECTION restent distinctes.
- Plusieurs tables de conduite plausibles, plusieurs distributions plausibles,
  ou des colonnes reconnues dupliquées : refus, sans choix arbitraire.
- Les feuilles sans en-têtes pertinents ne sont pas importées. Leurs erreurs de
  cellules sont signalées ; celles des feuilles retenues bloquent l’import.

## Conservation et validation

Les cellules sources, les en-têtes et le préambule de chaque table importée sont
conservés dans `document.import_source`, y compris les colonnes supplémentaires.
Cette archive survit à la sauvegarde/relecture du Builder. Elle décrit le fichier
importé, pas les modifications ultérieures des cues.

Les champs TC et TEXTE restent obligatoires dans les en-têtes ; un TC vide reste
permis pour un cue manuel. Des valeurs sous un en-tête vide ou au-delà des
colonnes nommées sont refusées plutôt que devinées.

Après normalisation, les règles métier existantes de `validate_builder_document`
restent appliquées. Un document non prêt est maintenant refusé dès l’import avec
le détail de `builder_import_values` (TC, texte, distribution, équipements,
affectations incohérentes). La sauvegarde directe des anciens documents et la
validation Builder → ShowCue restent inchangées.

La prévisualisation montre la feuille, la ligne d’en-têtes, l’encodage et les
avertissements. Aucune sauvegarde automatique n’est ajoutée.

## Correction complémentaire nécessaire

L’export nommait trois emplacements d’équipement mais écrivait huit emplacements
par ligne. Les en-têtes décrivent désormais les huit emplacements déjà pris en
charge. Un ancien fichier dont les valeurs n’ont pas d’en-têtes reste refusé avec
un diagnostic, sans attribuer arbitrairement ses colonnes.

## Vérification

Les fixtures sont synthétiques et reproduisent des structures d’export typiques
Numbers, Excel, LibreOffice et Google Sheets ; elles ne sont pas des exports
capturés depuis chaque logiciel. Les tests couvrent aussi les erreurs et
ambiguïtés, la persistance des cellules supplémentaires, les types XLSX,
les formules et les diagnostics HTTP. Aucun lancement d’Ableton n’est nécessaire.
