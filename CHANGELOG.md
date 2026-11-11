# Changelog

## 2026-11-11

- Poste maître (`ecritureCache` et `telechargementGitHub` à `true`) : si le MSI du dernier tag manque dans le cache (ex. partage inaccessible lors d'un passage précédent, cache local utilisé en repli), il est maintenant téléchargé et publié dans le cache même si l'application est déjà à jour localement. Avant, le cache partagé restait incomplet tant qu'aucune nouvelle version n'était installée.
- Commentaires du code source (`.ps1`) et CHANGELOG.md : accents rétablis ; BOM UTF-8 ajouté à `Update-ArtCraft.ps1` et `Uninstall-ArtCraft.ps1` pour que PowerShell 5.1 les lise correctement.

## 2026-10-27

- Remplacement de winget par un updater MSI systemwide : dernière version via redirection GitHub, vérification SHA256SUMS, cache partagé, configuration JSON.
- Un accès refusé au cache n'interrompt plus l'update : vérification et téléchargement directs depuis GitHub en repli.
- La tâche planifiée s'appelle maintenant "ArtCraft-SYSTEM-Updater" (ancien nom : "ArtCraft Auto Update").
- Nouvelle clé `telechargementGitHub` (défaut `true`) : `false` = mode cache seulement, aucun accès à GitHub.
- L'installateur ne fait plus l'installation initiale des applications : il crée la tâche planifiée et la démarre.
- `ecritureCache` et `telechargementGitHub` valent maintenant `false` par défaut (postes en cache seulement) ; le poste maître doit les mettre à `true`.
- La config centrale est fusionnée avec la config locale (au lieu de la remplacer) ; une liste `applications` vide n'est plus une erreur.
- La configuration d'un poste client peut rester limitée à `cheminCache` et `cheminConfigCentrale` ; la configuration centrale contient `applications`, `installerManquantes` et `reporterSiSessionOuverte`.
- Nouvelle clé `supprimerRaccourcisBureau` (défaut `true`) : à la fin de chaque exécution, suppression des raccourcis `<application>*.lnk` des applications configurées sur le bureau public (là où le MSI systemwide les crée).
- La détection d'une session active gère maintenant l'absence de session utilisateur quand `quser` retourne une erreur.
