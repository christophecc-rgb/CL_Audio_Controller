# Pré-test Lio Box → Live principal → Hot Backup

Résultat du 6 octobre 2026 : faisabilité partielle confirmée, suivi matériel complet non validé.

Pré-test sans matériel, sans connexion réseau et sans modification des scripts Lio Box ou de l'application installée. Les tests utilisent les vrais callbacks passifs de Show Control avec des notifications OSC simulées. Ils ne mesurent pas le délai entre les lecteurs.

## Résultats

- Un changement de clip Session détecté actualise la scène courante. Les notifications de plusieurs pistes pour la même scène ne répètent pas la publication du contexte.
- La détection ne commande actuellement ni le principal ni le backup.
- Relancer le même index de scène sans changement de playing_slot_index ne produit pas de nouvel événement exploitable dans ce callback.
- Après le début du show, une réponse selected_scene ne remplace pas le pointeur local de la télécommande. La navigation de la molette n'est donc pas suivie par ce mécanisme.
- Une notification spontanée is_playing n'est pas traitée comme un abonnement transport dans osc_reply. Les réponses demandées servent à actualiser l'état, sans fournir une identification complète des commandes Pause/Stop/reprise.
- Un clip lancé individuellement peut produire le même changement d'index qu'un lancement de scène. Ne pas convertir systématiquement chaque événement de piste en lancement complet de scène sur le backup.

## Conditions avant activation

Conserver le Lio Box directement relié au principal. Compléter les événements nécessaires via l'API Live/AbletonOSC, puis tester la sélection sans lecture, le relancement de la même scène, Pause/reprise, les locators et déplacements en Arrangement. Les commandes CL déjà copiées doivent être reconnues afin de ne pas être reproduites une seconde fois à leur confirmation. Un état initial à la connexion ne doit pas déclencher un GO. Le backup doit rester sans influence sur le principal.

Observer un départ après sa réalisation introduit un délai. En Session, la quantification du backup pourrait reporter son lancement : un test réel des réglages de quantification et du timing est indispensable avant toute validation d'exploitation.

## Validation

```
CL_SECURITY_DIRECTORY=/private/tmp/cl-liobox-preflight-security .venv/bin/python -m pytest tests/test_liobox_backup_preflight.py tests/test_passive_scene_listeners.py tests/test_hot_backup_sync.py -q
```

52 tests et 4 sous-tests réussis. La configuration de sécurité des tests est isolée des réglages de l'application installée. Aucun suivi Lio Box → backup n'a été activé par ce pré-test.
