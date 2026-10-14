# Confirmation de connexion Ableton

Le rafraîchissement FULL vérifie l'identité du Set dans
`refresh_live_set_identity()` puis le transport dans
`refresh_names_and_transport()` de `app.py`.

Une absence de première réponse file_path interrompt désormais la vérification :
un timeout n'est pas une réponse confirmant un Set non enregistré. Une réponse
valide contenant une chaîne vide garde le traitement existant des Sets non enregistrés.

Si la seconde confirmation manque, si les deux chemins diffèrent ou si la sonde
du transport expire, le rafraîchissement renvoie False et expose connected=False
avec « AbletonOSC indisponible », uniquement pour la génération toujours courante.
Auparavant, l'échec d'identité renvoyait None puis False sans effacer connected,
et l'échec de la sonde transport pouvait atteindre le retour de succès.

Les réponses d'une génération précédente ne déconnectent pas une nouvelle
génération et ne la déclarent pas connectée à tort. Une confirmation complète
ultérieure peut reconnecter normalement le même runtime.
La correction ne réinitialise pas la scène sélectionnée, la scène jouée ou les
listeners passifs ; les transitions de Set et le bootstrap conservent leurs chemins.

`OSCTransport.query_locked()` renvoie None après timeout. Il actualise son propre
état de transport, mais celui-ci ne remplaçait pas automatiquement le champ
connected du host. Aucun changement de protocole OSC n'est nécessaire : le
correctif se situe dans le propriétaire de l'état exposé, app.py.

Régression : `tests/test_ableton_connection_confirmation.py` teste première et
seconde réponses manquantes, incohérence d'identité, transport non confirmé,
reconnexion, conservation des scènes, statut remote et concurrence de générations.
Les tests existants couvrent les changements de Set, Sets non enregistrés,
générations, callbacks/listeners passifs, OSC et GO Arrangement après pause.
Les réponses sont simulées ; aucune qualification matérielle n'est implicite.
