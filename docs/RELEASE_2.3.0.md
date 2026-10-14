# CL Kit et CL Kit Light 2.3.0

Version 2.3.0 — build 23001. Candidats de release, publication en attente de qualification finale.

- Nouveau CL Kit Light : interface dédiée, GO, scènes courante et préparée, précédent/suivant/STOP, durée courante et préparée, écoulé et restant.
- Moteur commun FULL/Light pour Ableton, GO, suivi des scènes, timing et accès distant sécurisé.
- Runtime Light historique exclu du package distribué ; conservé dans les sources de développement.
- Security Panel simplifié : état Configuration indépendant du déverrouillage administrateur, armement explicite et demandes d’approbation.
- Sortie du Mode spectacle protégée par le déverrouillage administrateur.
- Reconnexion et récupération du Set Light vérifiées avec Ableton réel depuis l’archive distribuée.
- Couverture automatisée du moteur commun, de la sécurité et du packaging renforcée.

FULL conserve ses fonctions ; Light ne démarre pas les services consoles, RTP consoles, backups ou LTC/MTC.
Les identités distinctes permettent une installation côte à côte. Fermer FULL avant de lancer Light : l’exécution simultanée n’est pas prise en charge.
Les applications sont signées ad hoc, sans notarisation Apple. Aucun mot de passe, appareil appairé ou certificat privé utilisateur n’est distribué.

## Validation technique

JavaScript : 27/27 suites. Python complet de la passe précédente : 1353 réussis, 1 ignoré, 122 sous-tests ; un échec préexistant du mock natif CLMemoryDefaults (stringForKey absent), indépendant du packaging. Nouvelle passe ciblée : 37 tests et 3 sous-tests réussis.

Les archives existantes n’ont pas été reconstruites. Signatures deep/strict, versions et architectures universal2 vérifiées après nouvelle extraction. Correction de déconnexion FULL : une absence de réponse transport marque explicitement AbletonOSC indisponible et interrompt le refresh. Régression succès → timeout → reconnexion couverte. La reconstruction révèle toutefois une autre sortie anticipée sur absence de confirmation d’identité du Set ; FULL reste non qualifié pour la déconnexion réelle. Voir le rapport final.

Validation iPhone physique en attente utilisateur. Mac vierge physique non testé.

Voir RELEASE_2.3.0_FINAL_QUALIFICATION.md pour le détail des contrôles, limites, fichiers proposés et exclusions.
