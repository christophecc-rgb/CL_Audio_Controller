# Temps locaux LOCAL_LIGHT

AbletonOSC installé expose les propriétés Clip avec une réponse `(track, slot, value)` :
`is_audio_clip`, `warping`, `looping`, `is_recording`, `loop_start`, `loop_end`, `playing_position`.
Il ne fournit pas une durée globale de scène.

Source : `abletonosc/clip.py`, ClipHandler.init_api, et
https://docs.cycling74.com/apiref/lom/clip/ .

La référence déterministe est la piste de plus petit index dont le slot réellement
joué correspond à la scène observée. Les autres clips ne sont pas sondés pour
leur durée. Aucun clip de la scène préparée n'est interrogé.

Pour ce clip de référence, audio sans Warp, non bouclé et non enregistré :
- durée = loop_end − loop_start ;
- écoulé = playing_position − loop_start ;
- restant = loop_end − playing_position.
Ces propriétés sont en secondes pour l'audio sans Warp. La plage et toutes les
réponses doivent être valides. Les clips MIDI ou avec Warp expriment leur temps
en battements : sans carte de tempo, on ne prétend pas fournir des secondes
exactes. Dans ces cas, ainsi que pour une boucle, un enregistrement ou une
réponse manquante, les trois champs valent null et l'interface affiche « — ».

Cette durée est celle du clip de référence, pas une promesse de fin de tous les
clips de la scène. Pour choisir une autre référence, réordonner les pistes ;
aucune durée n'est inventée à partir du nom de la scène.

L'acquisition optionnelle utilise le worker local existant, après le refresh du
Set, hors transaction GO. Pas de nouveau thread, de scan du Set, de timer externe
ni de dépendance FULL. Chaque lecture optionnelle expire après 25 ms et utilise
la file normale OSC : GO conserve sa priorité entre lectures. Une lecture OSC
déjà en cours peut occuper la file jusqu'à ces 25 ms ; GO n'attend jamais que la
mesure complète soit disponible et ne dépend jamais de son résultat.

Les résultats sont invalidés sur changement de génération, de scène ou de slots,
STOP et perte de connexion. Aucune extrapolation UI : seules les mesures backend
sont affichées, avec un rafraîchissement de statut à 750 ms.
