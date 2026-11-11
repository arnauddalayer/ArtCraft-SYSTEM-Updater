# Changelog

## 2026-11-11

- Poste maitre (`ecritureCache` et `telechargementGitHub` a `true`) : si le MSI du dernier tag manque dans le cache (ex. partage inaccessible lors d'un passage precedent, cache local utilise en repli), il est maintenant telecharge et publie dans le cache meme si l'application est deja a jour localement. Avant, le cache partage restait incomplet tant qu'aucune nouvelle version n'etait installee.

## 2026-10-27

- Remplacement de winget par un updater MSI systemwide : derniere version via redirection GitHub, verification SHA256SUMS, cache partage, configuration JSON.
- Un acces refuse au cache n'interrompt plus l'update : verification et telechargement directs depuis GitHub en repli.
- La tache planifiee s'appelle maintenant "ArtCraft-SYSTEM-Updater" (ancien nom : "ArtCraft Auto Update").
- Nouvelle cle `telechargementGitHub` (defaut `true`) : `false` = mode cache seulement, aucun acces a GitHub.
- L'installateur ne fait plus l'installation initiale des applications : il cree la tache planifiee et la demarre.
- ecritureCache et 	elechargementGitHub valent maintenant alse par defaut (postes en cache seulement) ; le poste maitre doit les mettre a 	rue.
- La config centrale est fusionnee avec la config locale (au lieu de la remplacer) ; une liste pplications vide n'est plus une erreur.
- La configuration d'un poste client peut rester limitee a `cheminCache` et `cheminConfigCentrale` ; la configuration centrale contient `applications`, `installerManquantes` et `reporterSiSessionOuverte`.
- Nouvelle cle `supprimerRaccourcisBureau` (defaut `true`) : a la fin de chaque execution, suppression des raccourcis `<application>*.lnk` des applications configurees sur le bureau public (la ou le MSI systemwide les cree).
- La detection d'une session active gere maintenant l'absence de session utilisateur quand `quser` retourne une erreur.
