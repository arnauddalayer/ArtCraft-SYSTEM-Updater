# ArtCraft-SYSTEM-Updater

Installe et met à jour les applications [ArtCraft](https://getartcraft.com/apps) en **MSI systemwide** (`ALLUSERS=1`, `Program Files`) sur les postes d'un laboratoire, depuis le compte `SYSTEM`.

- Dernière version trouvée via la redirection `github.com/storytold/<app>/releases/latest` (aucun appel à l'API GitHub, donc pas de quota).
- MSI vérifié avec le `SHA256SUMS.txt` de la release ; un fichier non listé ou au hash différent est refusé.
- **Cache partagé** (dossier sur un serveur) : le premier poste qui voit une nouvelle version la télécharge et alimente le cache ; les autres copient depuis le partage.
- Tâche planifiée `SYSTEM` toutes les heures (+ délai aléatoire de 10 min).
- Liste des applications définie par un fichier de configuration (optionnellement centralisé).

> Projet communautaire, **non affilié** à ArtCraft ni à storytold. Les noms d'applications appartiennent à leurs propriétaires respectifs.

## Contenu de `src/`

| Fichier | Rôle |
|---|---|
| [Update-ArtCraft.ps1](src/Update-ArtCraft.ps1) | Script principal exécuté par la tâche : trouve la dernière version, télécharge/vérifie le MSI (SHA-256), alimente ou lit le cache, installe avec `msiexec`, tient les journaux. Paramètres : `-cheminConfig`, `-dryRun`, `-forcer`. |
| [Install-ArtCraft.ps1](src/Install-ArtCraft.ps1) | Copie les fichiers dans `C:\ProgramData\ArtCraft-SYSTEM-Updater`, crée la tâche planifiée `ArtCraft-SYSTEM-Updater` (SYSTEM) et la démarre. N'installe pas les applications. |
| [Uninstall-ArtCraft.ps1](src/Uninstall-ArtCraft.ps1) | Retire la tâche, désinstalle les applications de la config (sauf avec `-conserverApplications`) et supprime le dossier de l'updater. |
| [Update-ArtCraft.example.json](src/Update-ArtCraft.example.json) | Modèle de configuration versionné. |
| `Update-ArtCraft.json` | Configuration réelle / tests locaux (ignorée par git). Copiée par l'installateur, à défaut l'exemple. |
| [_install.bat](src/_install.bat) | Lanceur de déploiement : appelle `Install-ArtCraft.ps1`. |
| [_uninstall.bat](src/_uninstall.bat) | Lanceur : désinstalle la tâche, l'updater **et** les applications. |
| [_uninstall-tache.bat](src/_uninstall-tache.bat) | Lanceur : désinstalle la tâche et l'updater, conserve les applications. |

## Installation

1. Copier [src/Update-ArtCraft.example.json](src/Update-ArtCraft.example.json) en `src/Update-ArtCraft.json` (ignoré par git) et l'éditer (voir ci-dessous). Sans `Update-ArtCraft.json`, l'installateur utilise l'exemple.
2. Sur chaque poste, en administrateur (ou via votre outil de déploiement, voir [src/_install.bat](src/_install.bat)) : exécuter `Install-ArtCraft.ps1`. Cela copie les fichiers dans `C:\ProgramData\ArtCraft-SYSTEM-Updater`, crée la tâche `ArtCraft-SYSTEM-Updater` et la démarre. L'installateur n'installe pas les applications : c'est la tâche qui s'en charge (au démarrage, puis toutes les heures). Si un utilisateur est connecté, les installations sont reportées jusqu'à ce que la session soit fermée (voir `reporterSiSessionOuverte`).

## Désinstallation

Exécuter en administrateur : [src/_uninstall.bat](src/_uninstall.bat) (tâche, updater **et** applications) ou [src/_uninstall-tache.bat](src/_uninstall-tache.bat) (tâche et updater seulement, applications conservées ; utile pour tester l'installateur). Les deux appellent `Uninstall-ArtCraft.ps1`. Le script complet supprime la tâche planifiée, désinstalle les applications listées dans `applications` (MSI machine) et supprime `C:\ProgramData\ArtCraft-SYSTEM-Updater`. Avec `-conserverApplications`, seuls la tâche et les fichiers de l'updater sont retirés. Le cache partagé n'est pas touché.

## Configuration

| Clé | Défaut | Rôle |
|---|---|---|
| `applications` | – | Applications à installer/maintenir : `PhotoCraft`, `VectorCraft`, `FilmCraft`, `LightCraft`, `PdfCraft`, `EffectCraft`, `DesignCraft`, `FigCraft`, `WordCraft`, `SoundCraft`, `DeckCraft`, `CadCraft`, `GridCraft`. Le préfixe `ArtCraft.` est accepté. |
| `organisation` | `storytold` | Organisation GitHub des dépôts. |
| `cheminCache` | vide | Dossier partagé (ex. `\\\\serveur\\partage\\ArtCraft`, antislashs doublés en JSON). Vide ou inaccessible : cache local `C:\ProgramData\ArtCraft-SYSTEM-Updater\Cache`. |
| `ecritureCache` | `false` | `true` pour le poste « maître » qui alimente le cache ; `false` pour les postes en lecture seule. Avec `telechargementGitHub: true`, le maître complète aussi le cache quand le MSI du dernier tag y manque, même si l'application est déjà à jour (ex. partage redevenu accessible après un repli sur le cache local). |
| `telechargementGitHub` | `false` | `false` = **cache seulement** : le poste n'accède jamais à GitHub. Il lit le dernier tag dans `latest.txt` et le MSI dans le cache ; si l'un manque ou si le partage est inaccessible, il le journalise et réessaie à la prochaine exécution, sans erreur. **Au moins un poste doit mettre `true`** (avec `ecritureCache: true`) pour alimenter le cache ; sans cela, rien n'est jamais téléchargé ni installé. |
| `dureeCacheDernierTagMinutes` | `60` | Durée pendant laquelle le tag « latest » mis en cache est réutilisé sans interroger GitHub. |
| `versionsAConserver` | `2` | Nombre de versions conservées par application dans le cache. |
| `installerManquantes` | `true` | Installe les applications absentes (sinon, ne fait que mettre à jour). |
| `reporterSiSessionOuverte` | `true` | Reporte les installations tant qu'une session est active (le cache est quand même alimenté). |
| `supprimerRaccourcisBureau` | `true` | À la fin de chaque exécution, supprime les raccourcis `<application>*.lnk` des applications configurées sur le bureau public (là où le MSI systemwide les crée). Avec `-dryRun`, les raccourcis sont seulement listés. |
| `cheminConfigCentrale` | vide | Chemin d'un `Update-ArtCraft.json` central (ex. sur le partage) **fusionné** avec la config locale s'il est accessible : ses clés remplacent celles du local, les clés absentes gardent la valeur locale. Permet de changer la liste d'apps pour tout le labo sans redéployer. Inaccessible : la config locale seule est utilisée. |

### Exemple commenté

À titre de documentation seulement : **retirer les commentaires** (`//`) dans le vrai fichier, car le JSON n'en accepte pas et l'updater ne pourrait pas le lire.

```jsonc
{
  // Applications à installer et maintenir (le préfixe "ArtCraft." est accepté)
  "applications": [
    "PhotoCraft",
    "VectorCraft",
    "FilmCraft",
    "PdfCraft"
  ],

  // Organisation GitHub des dépôts (github.com/<organisation>/<app en minuscules>)
  "organisation": "storytold",

  // Cache partagé ; antislashs doublés en JSON. Vide = cache local ProgramData
  "cheminCache": "\\\\serveur\\partage\\ArtCraft",

  // true : ce poste peut écrire dans le cache (poste « maître »). false (défaut) : lecture seule
  "ecritureCache": false,

  // true : peut télécharger depuis GitHub. false (défaut) : cache seulement, aucun accès à GitHub
  "telechargementGitHub": false,

  // Durée (minutes) pendant laquelle le dernier tag en cache est réutilisé sans interroger GitHub
  "dureeCacheDernierTagMinutes": 60,

  // Nombre de versions conservées par application dans le cache
  "versionsAConserver": 2,

  // Installer aussi les applications absentes (sinon, mise à jour seulement)
  "installerManquantes": true,

  // Reporter les installations tant qu'un utilisateur a une session ouverte
  "reporterSiSessionOuverte": true,

  // Supprimer les raccourcis des applications configurées sur le bureau public
  "supprimerRaccourcisBureau": true,

  // Config centrale (ex. sur le partage), fusionnée avec celle-ci si accessible (ses clés l'emportent). Vide = désactivé
  "cheminConfigCentrale": "\\\\serveur\\partage\\ArtCraft\\Update-ArtCraft.json"
}
```

### Exemple : poste maître

Télécharge depuis GitHub, alimente le cache partagé et installe les applications. Un seul poste du labo.

```json
{
  "applications": ["PhotoCraft", "VectorCraft", "FilmCraft", "PdfCraft"],
  "cheminCache": "\\\\serveur\\partage\\ArtCraft",
  "ecritureCache": true,
  "telechargementGitHub": true
}
```

### Exemple : poste client

Ne fait que consommer le cache du poste maître : aucun accès à GitHub, aucune écriture sur le partage. `ecritureCache` et `telechargementGitHub` valent `false` par défaut, il suffit donc de ne pas les mentionner.

```json
{
  "cheminCache": "\\\\serveur\\partage\\ArtCraft",
  "cheminConfigCentrale": "\\\\serveur\\partage\\ArtCraft\\Update-ArtCraft.json"
}
```

Pour ne pas répéter la liste des applications sur chaque poste client, la mettre dans une config centrale (sur le partage). Le fichier central peut rester limité aux paramètres communs à tous les postes :

```json
{
  "applications": ["PhotoCraft", "VectorCraft", "FilmCraft", "PdfCraft"],
  "installerManquantes": true,
  "reporterSiSessionOuverte": true
}
```

`organisation` est facultatif (défaut : `storytold`). Les paramètres de cache et de téléchargement (`cheminCache`, `ecritureCache`, `telechargementGitHub`, `dureeCacheDernierTagMinutes` et `versionsAConserver`) restent dans la configuration du poste maître ou prennent leurs valeurs par défaut sur les postes clients. Une liste `applications` vide ou absente (par exemple un poste dont la config locale ne contient que `cheminConfigCentrale`, avec le partage inaccessible) n'est pas une erreur : le script le journalise et ne fait rien.

### Permissions du partage

La tâche tourne en `SYSTEM` : l'accès réseau se fait avec le compte machine (`DOMAINE\POSTE$`). Donner à **Ordinateurs du domaine** (ou à un groupe de vos postes) le droit *Lecture* sur le partage et le NTFS ; *Modification* pour les postes qui alimentent le cache (ou un seul poste « maître » avec `ecritureCache: true`, les autres gardent le défaut `false`).

> **Sécurité** : le cache est de confiance. Le hash est vérifié contre un `SHA256SUMS.txt` stocké aussi dans le cache, donc quiconque peut écrire sur le partage peut y substituer un MSI et ses sommes, et le faire installer en `SYSTEM` sur tous les postes. N'accordez l'écriture qu'au seul poste maître.

Par défaut (`telechargementGitHub: false`, `ecritureCache: false`), un poste n'utilise que le cache et ne contacte jamais GitHub : si le cache est inaccessible ou vide, il le journalise et réessaie à la prochaine exécution. Seul le poste « maître » doit avoir `telechargementGitHub: true` et `ecritureCache: true` pour alimenter le cache. Avec `telechargementGitHub: true`, un poste qui n'a pas accès au cache se rabat sur GitHub. Donner au compte machine les droits de lecture sur le partage.

## Utilisation

```powershell
# Voir ce qui serait fait, sans rien télécharger ni installer
C:\ProgramData\ArtCraft-SYSTEM-Updater\Update-ArtCraft.ps1 -dryRun
# Forcer même si un utilisateur est connecté
C:\ProgramData\ArtCraft-SYSTEM-Updater\Update-ArtCraft.ps1 -forcer
```

Journaux dans `C:\ProgramData\ArtCraft-SYSTEM-Updater\Logs` (un fichier par jour + un journal `msiexec` par installation, conservés 30 jours). Code de sortie `1` si au moins une application a échoué.

La version installée est lue dans le registre `HKLM` (nom d'affichage = nom de l'app) : les installations « utilisateur » du launcher officiel ne sont pas détectées.

## Changelog et licence

Voir [CHANGELOG.md](CHANGELOG.md). Ce projet est distribué sous licence MIT (voir [LICENSE](LICENSE)).

# Utilisation de l'IAg

La création de ce projet a été réalisée avec l’IA (en local avec gemma4:12b via Ollama, et avec Github Copilot en mode auto).

<img alt="Réalisé avec l'IA" loading="lazy" src="https://d1qywhc7l90rsa.cloudfront.net/accounts/152505/images/Label-IA_fondclair.png" width="200" height="80">
