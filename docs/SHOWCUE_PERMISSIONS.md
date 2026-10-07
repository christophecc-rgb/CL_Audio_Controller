# Autorisations ShowCue et notes par poste

Les écritures distantes réutilisent RemoteSecurity : appareil appairé, signature
HMAC, nonce, horodatage, expiration/révocation et télécommandes armées. HTTPS est
obligatoire pour les écritures ShowCue. Aucun déverrouillage local ni mode
développement n'est requis pour ces écritures distantes dédiées.

## Appareil

```json
{
  "permissions": {"go": true, "edit_cues": true, "edit_notes": true},
  "posts": ["FOH", "RETOURS"]
}
```

Sans ces nouveaux champs, GO conserve le droit du rôle (operator/admin : oui,
reader : non). edit_cues et edit_notes sont faux, posts est vide. Aucun nouveau
droit d'édition n'est implicitement donné, y compris aux anciens administrateurs.
Un champ GO explicite remplace ce fallback. Les autres commandes de spectacle
conservent leur contrôle de rôle existant. Le GO transactionnel n'est pas modifié.

L'administration locale déverrouillée, en mode développement, configure les
permissions depuis la fiche de chaque appareil. Modifier les droits ne transforme
pas l'appareil en administrateur. Les changements sont vérifiés côté serveur à
chaque requête, sans refaire l'appairage.

## Routes

| Route | Permission distante |
|---|---|
| POST /action avec action=go | go, puis contrôles techniques existants |
| POST /show-info/cues | edit_cues |
| PUT /show-info/cues/<id> | edit_cues |
| DELETE /show-info/cues/<id> | edit_cues |
| PUT /show-info/cues/<id>/notes/<post> | edit_notes et poste autorisé |
| PUT /show-info/cues/<id>/notes/GENERAL | edit_cues |
| Builder, casting/distribution, réseau, sécurité, système | administration existante |

L'administration locale reste nécessaire aux écritures locales. Les lectures
ShowCue restent publiques comme auparavant ; les permissions restreignent les
écritures, pas la confidentialité des notes.

## Cue

```json
{
  "builder": {
    "notes": "Note générale existante",
    "notes_by_post": {
      "FOH": "Note FOH\nDeuxième ligne",
      "RETOURS": "Note retours",
      "PLATEAU": "Note plateau",
      "LUMIERE": "Note lumière"
    }
  }
}
```

notes_by_post est optionnel ; absent, il est lu comme un objet vide. Les notes
sont des chaînes de 10000 caractères maximum. Une chaîne vide efface la note du
poste. Le corps de la route dédiée accepte exclusivement session_id et text.
La mise à jour sous verrou recharge le document et fusionne une seule clé.
Une édition générale conserve toujours les notes de postes actuelles, même si
le client avait une ancienne copie. Une écriture distante directe de
builder.notes_by_post est refusée : utiliser la route dédiée.

Les anciennes notes générales ne sont pas déplacées. Le stockage Builder,
la récupération et la génération de nouveaux cues transportent les notes par
poste ; une mise à jour d'un cue déjà existant préserve ses notes actuelles.
Les exports tabulaires existants ne changent pas de colonnes.

## Interface et limites

La carte Live affiche la note du poste courant puis la note générale. La modale
édite d'abord le poste courant ; GENERAL est proposé au Mac local et aux appareils
avec edit_cues. La note générale peut aussi être modifiée dans l'éditeur complet.
Le serveur reste l'autorité, même si un client contourne les restrictions UI.
Les erreurs affichent le statut HTTP et message/error ; les réponses non JSON
sont signalées explicitement.

Les éditions simultanées de postes différents ne se remplacent pas. Deux
éditions simultanées du même poste utilisent la dernière écriture acceptée.
Le changement de session pendant une édition reste refusé avec 409.
La gestion des droits est par appareil, avec le nom d'opérateur existant ; il
n'existe pas de nouveau compte utilisateur partagé entre plusieurs appareils.
