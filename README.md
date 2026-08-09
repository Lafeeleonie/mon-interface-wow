# Mon interface WoW

Version publique et assainie de mon interface World of Warcraft Retail.

## Contenu

- `Interface/AddOns/` : les addons installés, sans les bases de joueurs générées ni les addons contenant mes médias personnels ;
- `WTF/Account/ACCOUNT/SavedVariables/` : une sélection de profils d'interface utiles ;
- `Build-Public-Snapshot.ps1` : le script qui reconstruit cette version publique à partir de mon installation locale.

Les noms de compte, royaumes et personnages sont remplacés par des valeurs génériques. Les BattleTags, e-mails, GUID, adresses IP, identifiants Discord, chemins utilisateur, webhooks et valeurs ressemblant à des secrets sont également neutralisés.

Ne sont volontairement pas publiés : historiques de discussion, combat, enchères et guilde, macros, caches, fichiers propres aux personnages, captures d'écran, journaux, polices générées, sauvegardes temporaires et archives de profils supprimés.

## Installation

1. Fermer World of Warcraft.
2. Copier `Interface` dans le dossier `_retail_`.
3. Pour récupérer les profils partagés, copier les fichiers de `WTF/Account/ACCOUNT/SavedVariables` dans le dossier `WTF/Account/<votre-compte>/SavedVariables`.
4. Lancer WoW et sélectionner/importer les profils voulus dans chaque addon.

Certains addons peuvent être désactivés ou incompatibles après une mise à jour du jeu. Les gestionnaires d'addons restent la meilleure manière de recevoir leurs mises à jour officielles.

## Mise à jour de la version publique

Le dépôt doit être placé à côté du dossier `_retail_`. Depuis ce dépôt, avec WoW fermé :

```powershell
.\Build-Public-Snapshot.ps1
git status
```

Le script applique de nouveau la liste blanche de réglages et toutes les règles d'assainissement avant publication.
