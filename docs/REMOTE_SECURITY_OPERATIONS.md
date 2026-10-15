# Télécommandes : appairage, rôles et armement

L’appairage conserve l’identité, la clé hachée et le rôle de l’appareil dans
`security.json`. Aucune nouvelle base ni rotation des identifiants n’est introduite.

| Rôle existant | Présentation | Accès |
| --- | --- | --- |
| `admin` | Administrateur | Commandes et administration selon les protections existantes |
| `operator` | Opérateur / Télécommande | Commandes de spectacle ; GO et édition selon les grants existants |
| `reader` | ShowQ uniquement | Consultation, aucune commande ni édition |

Les grants enregistrés restent conservés. Le rôle `reader` les neutralise tant
qu’il est sélectionné, même si un ancien grant GO ou édition était présent.
Les droits d’édition des opérateurs et administrateurs restent explicites.
La consultation des routes ShowCue déjà publiques n’est pas restreinte.

## Armement

- Sans choix explicite, approuver un administrateur ou un opérateur arme les
  commandes. Un lecteur n’active pas l’armement.
- Le choix explicite Armer/Désarmer est enregistré dans `remote_armed` (booléen).
  Il reste valable au redémarrage et n’est pas écrasé par un nouvel appairage.
- Les anciennes données sans ce champ utilisent le défaut automatique : les
  appareils de commande ayant encore une autorisation valide sont armés.
  L’ancien état volatile ne peut pas être récupéré.
- L’entrée explicite en mode spectacle arme les commandes et conserve les rôles.
  Elle désactive toujours le développement persistant et le déverrouillage local.
- Verrouiller l’administration ou la déverrouiller ne modifie pas l’armement.
- Un appareil inconnu, révoqué ou dont l’autorisation a expiré reste refusé,
  même si l’état global indique « armé ». Signatures, nonces et horodatages restent
  obligatoires pour les commandes distantes.
- Le désarmement ne bloque ni la consultation ShowCue ni le heartbeat signé.

Les autorisations permanentes gardent leur validité au redémarrage. Les prises
de poste temporaires gardent leur limite de durée et de session ; elles ne sont
pas converties en autorisations permanentes. Le changement de mot de passe et
la révocation conservent leurs protections existantes.

## Page de sécurité

Exploitation et appareils apparaissent en premier ; l’administration est une
colonne secondaire sur Mac. Le seul toggle Armer/Désarmer reflète l’état global.
Chaque appareil affiche séparément son autorisation, son rôle, sa connexion et
son armement effectif. Le rôle peut être choisi lors de l’approbation puis modifié
en mode configuration. Les permissions détaillées sont repliables.

Les confirmations sont centralisées et temporaires ; l’armement est confirmé
par son badge et le libellé du toggle. Le développement persistant dispose d’un
état explicite et d’un contrôle Activer/Désactiver qui conserve le mécanisme
local existant. Les URL et QR dynamiques du panneau principal, ainsi que les
mécanismes TLS, restent inchangés.
