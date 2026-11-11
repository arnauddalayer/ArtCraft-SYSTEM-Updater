<#
.SYNOPSIS
    Installe / met a jour les applications ArtCraft en MSI "systemwide" (ALLUSERS=1).

.DESCRIPTION
    - Trouve la derniere version via la redirection github.com/<org>/<app>/releases/latest
      (aucune consommation du quota de l'API GitHub).
    - Telecharge le MSI de l'architecture courante et le verifie avec le SHA256SUMS.txt de la release.
    - Utilise un cache partage (cheminCache, ex. \\serveur\partage\ArtCraft) : le premier poste qui
      trouve une nouvelle version alimente le cache, les autres ne telechargent rien depuis Internet.
    - Concu pour tourner en SYSTEM depuis une tache planifiee.

.PARAMETER cheminConfig
    Fichier de configuration JSON (par defaut : Update-ArtCraft.json a cote du script).

.PARAMETER dryRun
    Affiche ce qui serait fait sans rien telecharger ni installer.

.PARAMETER forcer
    Installe meme si un utilisateur est connecte.
#>
[CmdletBinding()]
param(
    [string]$cheminConfig = "",
    [switch]$dryRun,
    [switch]$forcer
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
if (!$cheminConfig) { $cheminConfig = Join-Path $PSScriptRoot "Update-ArtCraft.json" }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dossierRacine = Join-Path $env:ProgramData "ArtCraft-SYSTEM-Updater"
$dossierJournaux = Join-Path $dossierRacine "Logs"
$dossierTemporaire = Join-Path $dossierRacine "Staging"
$cacheLocal = Join-Path $dossierRacine "Cache"
$fichierSommes = "SHA256SUMS.txt"

foreach ($dossier in $dossierRacine, $dossierJournaux, $dossierTemporaire) {
    if (!(Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
}

Start-Transcript -Path (Join-Path $dossierJournaux ("Update-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))) -Append | Out-Null

# Une seule execution a la fois (le mutex est libere automatiquement si le processus meurt)
$mutex = New-Object System.Threading.Mutex($false, "Global\ArtCraftSystemUpdater")
$possedeMutex = $false
$echecs = 0

function ecrireJournal([string]$message) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $message)
}

function obtenirParametre($config, [string]$nom, $valeurDefaut) {
    $propriete = $config.PSObject.Properties[$nom]
    if ($null -eq $propriete -or $null -eq $propriete.Value -or "$($propriete.Value)" -eq "") { return $valeurDefaut }
    return $propriete.Value
}

function obtenirArchitecture {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        "x86"   { "x86" }
        default { throw "Architecture non supportee : $arch" }
    }
}

function convertirEnVersion([string]$texte) {
    if ($texte -match '(\d+(\.\d+){1,3})') { return [version]$Matches[1] }
    return $null
}

function obtenirVersionInstallee([string]$nomAffiche) {
    $cles = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $entree = Get-ItemProperty -Path $cles -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -ieq $nomAffiche } |
        Select-Object -First 1
    if ($entree) { return convertirEnVersion $entree.DisplayVersion }
    return $null
}

# Derniere version via la redirection /releases/latest -> /releases/tag/<tag> (sans API)
function obtenirDernierTagGitHub([string]$organisation, [string]$depot) {
    $requete = [Net.HttpWebRequest]::Create("https://github.com/$organisation/$depot/releases/latest")
    $requete.AllowAutoRedirect = $false
    $requete.Method = "HEAD"
    $requete.UserAgent = "ArtCraft-SYSTEM-Updater"
    $requete.Timeout = 30000
    $reponse = $requete.GetResponse()
    try {
        $destination = $reponse.Headers["Location"]
        $code = [int]$reponse.StatusCode
    }
    finally { $reponse.Close() }
    if (($code -ne 301 -and $code -ne 302) -or !$destination) {
        throw "Pas de redirection pour $organisation/$depot (HTTP $code)."
    }
    if ($destination -notmatch '/releases/tag/([^/?#]+)$') { throw "Redirection inattendue : $destination" }
    return [Uri]::UnescapeDataString($Matches[1])
}

# Tag le plus recent, en passant d'abord par le cache (partage ou local) pour limiter les requetes
function obtenirDernierTag([string]$organisation, [string]$depot, [string]$racineCache, [bool]$ecriturePermise, [int]$ageMaxMinutes, [bool]$githubPermis) {
    $fichierDernier = Join-Path (Join-Path $racineCache $depot) "latest.txt"
    $tagEnCache = $null
    try {
        if (Test-Path -LiteralPath $fichierDernier -ErrorAction Stop) {
            $tagEnCache = (Get-Content -LiteralPath $fichierDernier -TotalCount 1 -ErrorAction Stop).Trim()
            $age = (New-TimeSpan -Start (Get-Item -LiteralPath $fichierDernier -ErrorAction Stop).LastWriteTime -End (Get-Date)).TotalMinutes
            if ($tagEnCache -and $age -ge 0 -and $age -lt $ageMaxMinutes) { return $tagEnCache }
        }
    }
    catch {
        ecrireJournal "Lecture du cache latest         impossible pour $depot ($($_.Exception.Message))."
        $tagEnCache = $null
    }
            # Mode cache seulement : on se fie au dernier tag connu, aussi ancien soit-il
            if (!$githubPermis) { return $tagEnCache }
    try {
        $tag = obtenirDernierTagGitHub $organisation $depot
    }
    catch {
        if ($tagEnCache) {
            ecrireJournal "GitHub injoignable pour $depot ($($_.Exception.Message)), utilisation du cache : $tagEnCache"
            return $tagEnCache
        }
        throw
    }
    if ($ecriturePermise) {
        try {
            New-Item -ItemType Directory -Path (Split-Path $fichierDernier) -Force | Out-Null
            Set-Content -Path $fichierDernier -Value $tag -Encoding ASCII
        }
        catch { ecrireJournal "Ecriture de latest.txt impossible : $($_.Exception.Message)" }
    }
    return $tag
}

function obtenirHashAttendu([string]$cheminSommes, [string]$nomFichier) {
    foreach ($ligne in Get-Content $cheminSommes) {
        if ($ligne -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -eq $nomFichier) {
            return $Matches[1].ToLowerInvariant()
        }
    }
    return $null
}

function verifierFichier([string]$cheminFichier, [string]$cheminSommes, [string]$nomFichier) {
    if (!(Test-Path $cheminFichier) -or !(Test-Path $cheminSommes)) { return $false }
    $hashAttendu = obtenirHashAttendu $cheminSommes $nomFichier
    if (!$hashAttendu) { return $false }
    return ((Get-FileHash $cheminFichier -Algorithm SHA256).Hash.ToLowerInvariant() -eq $hashAttendu)
}

# Copie atomique : fichier temporaire puis renommage (plusieurs postes peuvent ecrire en meme temps)
function publierFichier([string]$source, [string]$destination) {
    $temporaire = "$destination.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Copy-Item $source $temporaire -Force
        if (Test-Path $destination) { return }
        Move-Item $temporaire $destination -Force
    }
    finally { Remove-Item $temporaire -Force -ErrorAction SilentlyContinue }
}

function supprimerAnciennesVersions([string]$cacheDepot, [int]$nombreAGarder) {
    Get-ChildItem $cacheDepot -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $nombreAGarder |
        ForEach-Object {
            ecrireJournal "Purge de l'ancienne version en cache : $($_.Name)"
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
}

# Retourne le chemin local (dossier temporaire) d'un MSI dont le SHA-256 est verifie
function obtenirMsiVerifie([string]$organisation, [string]$depot, [string]$tag, [string]$arch, [string]$racineCache, [bool]$ecriturePermise, [int]$nombreAGarder, [bool]$githubPermis) {
    $version = $tag.TrimStart("v")
    $nomFichier = "$depot-$version-windows-$arch.msi"
    $dossierCache = Join-Path (Join-Path $racineCache $depot) $tag
    $dossierTravail = Join-Path $dossierTemporaire "$depot-$tag"
    if (!(Test-Path $dossierTravail)) { New-Item -ItemType Directory -Path $dossierTravail -Force | Out-Null }
    $msiLocal = Join-Path $dossierTravail $nomFichier
    $sommesLocales = Join-Path $dossierTravail $fichierSommes

    $depuisCache = $false
    try {
        $msiEnCache = Join-Path $dossierCache $nomFichier
        $sommesEnCache = Join-Path $dossierCache $fichierSommes
        if ((Test-Path $msiEnCache) -and (Test-Path $sommesEnCache)) {
            Copy-Item $sommesEnCache $sommesLocales -Force
            Copy-Item $msiEnCache $msiLocal -Force
            if (verifierFichier $msiLocal $sommesLocales $nomFichier) {
                ecrireJournal "$nomFichier : trouve dans le cache ($dossierCache), SHA-256 valide."
                $depuisCache = $true
            }
            else { ecrireJournal "$nomFichier : copie en cache invalide, nouveau telechargement." }
        }
    }
    catch { ecrireJournal "Lecture du cache impossible ($($_.Exception.Message))." }

    if (!$depuisCache -and !$githubPermis) {
        ecrireJournal "$nomFichier : absent du cache et telechargement GitHub desactive (telechargementGitHub = false)."
        return $null
    }

    if (!$depuisCache) {
        $urlBase = "https://github.com/$organisation/$depot/releases/download/$tag"
        ecrireJournal "Telechargement de $nomFichier depuis GitHub..."
        Invoke-WebRequest "$urlBase/$fichierSommes" -OutFile $sommesLocales -UseBasicParsing
        if (!(obtenirHashAttendu $sommesLocales $nomFichier)) {
            throw "$nomFichier n'est pas liste dans $fichierSommes : fichier refuse."
        }
        Invoke-WebRequest "$urlBase/$nomFichier" -OutFile $msiLocal -UseBasicParsing
        if (!(verifierFichier $msiLocal $sommesLocales $nomFichier)) {
            Remove-Item $msiLocal -Force -ErrorAction SilentlyContinue
            throw "SHA-256 invalide pour $nomFichier : fichier supprime."
        }
        ecrireJournal "$nomFichier : SHA-256 valide."

        if ($ecriturePermise) {
            try {
                New-Item -ItemType Directory -Path $dossierCache -Force | Out-Null
                publierFichier $msiLocal (Join-Path $dossierCache $nomFichier)
                publierFichier $sommesLocales (Join-Path $dossierCache $fichierSommes)
                ecrireJournal "Cache alimente : $dossierCache"
                supprimerAnciennesVersions (Join-Path $racineCache $depot) $nombreAGarder
            }
            catch { ecrireJournal "Ecriture dans le cache impossible : $($_.Exception.Message)" }
        }
    }
    return $msiLocal
}

# Poste maitre : si le cache n'a pas le MSI du dernier tag (ex. partage inaccessible lors d'un passage precedent),
# on le telecharge et on l'y publie, meme si l'application est deja a jour localement.
function completerCache([string]$organisation, [string]$depot, [string]$tag, [string]$arch, [string]$racineCache, [bool]$ecriturePermise, [int]$nombreAGarder, [bool]$githubPermis) {
    if (!$ecriturePermise -or !$githubPermis -or $dryRun) { return }
    $nomFichier = "$depot-$($tag.TrimStart('v'))-windows-$arch.msi"
    $dossierCache = Join-Path (Join-Path $racineCache $depot) $tag
    try {
        if ((Test-Path -LiteralPath (Join-Path $dossierCache $nomFichier) -ErrorAction Stop) -and
            (Test-Path -LiteralPath (Join-Path $dossierCache $fichierSommes) -ErrorAction Stop)) { return }
    }
    catch { ecrireJournal "Verification du cache impossible pour $depot ($($_.Exception.Message))." }
    ecrireJournal "$nomFichier : absent du cache, alimentation du cache."
    $msi = obtenirMsiVerifie $organisation $depot $tag $arch $racineCache $ecriturePermise $nombreAGarder $githubPermis
    if ($msi) { Remove-Item (Split-Path $msi) -Recurse -Force -ErrorAction SilentlyContinue }
}

function installerMsi([string]$cheminMsi, [string]$nom) {
    $journalMsi = Join-Path $dossierJournaux ("msi-{0}-{1}.log" -f $nom, (Get-Date -Format "yyyyMMdd-HHmmss"))
    $arguments = "/i `"$cheminMsi`" /qn /norestart ALLUSERS=1 /l*v `"$journalMsi`""
    $processus = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
    switch ($processus.ExitCode) {
        0       { ecrireJournal "$nom installe." }
        3010    { ecrireJournal "$nom installe (redemarrage requis)." }
        1641    { ecrireJournal "$nom installe (redemarrage en cours)." }
        default { throw "msiexec a retourne $($processus.ExitCode) pour $nom (voir $journalMsi)." }
    }
}

function testerSessionActive {
    $sessions = @(& $env:ComSpec /c "quser 2>nul")
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($session in $sessions) {
        if ($session -match '\s(Active|Actif)\s') { return $true }
    }
    return $false
}

# Le MSI (ALLUSERS=1) cree ses raccourcis sur le bureau public uniquement
function supprimerRaccourcisBureau([string[]]$noms, [bool]$simulation) {
    $dossier = [Environment]::GetFolderPath("CommonDesktopDirectory")
    foreach ($nom in $noms) {
        $raccourcis = @(Get-ChildItem -LiteralPath $dossier -Filter "$nom*.lnk" -File -ErrorAction SilentlyContinue)
        foreach ($raccourci in $raccourcis) {
            try {
                if ($simulation) { ecrireJournal "Raccourci a supprimer : $($raccourci.FullName)"; continue }
                Remove-Item -LiteralPath $raccourci.FullName -Force -ErrorAction Stop
                ecrireJournal "Raccourci supprime : $($raccourci.FullName)"
            }
            catch { ecrireJournal "Raccourci non supprime ($($raccourci.FullName)) : $($_.Exception.Message)" }
        }
    }
}

try {
    $possedeMutex = $mutex.WaitOne(0)
    if (!$possedeMutex) {
        ecrireJournal "Une autre execution est deja en cours."
        return
    }

    ecrireJournal "=== Mise a jour ArtCraft ($env:COMPUTERNAME) ==="

    $config = Get-Content $cheminConfig -Raw | ConvertFrom-Json
    $cheminCentral = obtenirParametre $config "cheminConfigCentrale" ""
    if ($cheminCentral) {
        try {
            if (Test-Path -LiteralPath $cheminCentral -ErrorAction Stop) {
                $centrale = Get-Content -LiteralPath $cheminCentral -Raw -ErrorAction Stop | ConvertFrom-Json
                # Fusion : les cles de la config centrale remplacent celles de la config locale
                foreach ($propriete in $centrale.PSObject.Properties) {
                    if ($propriete.Name -ne "cheminConfigCentrale") {
                        $config | Add-Member -NotePropertyName $propriete.Name -NotePropertyValue $propriete.Value -Force
                    }
                }
                ecrireJournal "Configuration centrale fusionnee : $cheminCentral"
            }
            else { ecrireJournal "Configuration centrale introuvable ($cheminCentral), configuration locale utilisee." }
        }
        catch { ecrireJournal "Configuration centrale illisible ($($_.Exception.Message)), configuration locale utilisee." }
    }

    $organisation = obtenirParametre $config "organisation" "storytold"
    $cheminCache = obtenirParametre $config "cheminCache" ""
    $ecriturePermise = [bool](obtenirParametre $config "ecritureCache" $false)
    $githubPermis = [bool](obtenirParametre $config "telechargementGitHub" $false)
    $ageMax = [int](obtenirParametre $config "dureeCacheDernierTagMinutes" 60)
    $nombreAGarder = [int](obtenirParametre $config "versionsAConserver" 2)
    $installerManquantes = [bool](obtenirParametre $config "installerManquantes" $true)
    $ignorerSiSessionOuverte = [bool](obtenirParametre $config "reporterSiSessionOuverte" $true)
    $supprimerRaccourcis = [bool](obtenirParametre $config "supprimerRaccourcisBureau" $true)
    $applications = @($config.applications | Where-Object { "$_".Trim() })
    if ($applications.Count -eq 0) { ecrireJournal "Aucune application configuree (cle 'applications' vide ou absente), rien a faire." }

    $racineCache = $cacheLocal
    if ($cheminCache) {
        try {
            if (Test-Path -LiteralPath $cheminCache -ErrorAction Stop) { $racineCache = $cheminCache }
            else { ecrireJournal "Cache partage inaccessible ($cheminCache), cache local utilise." }
        }
        catch {
            ecrireJournal "Verification du cache partage impossible ($cheminCache : $($_.Exception.Message)), cache local utilise."
        }
    }
    ecrireJournal "Cache : $racineCache (ecriture : $ecriturePermise)"

    $arch = obtenirArchitecture
    $sessionActive = (!$forcer -and $ignorerSiSessionOuverte -and (testerSessionActive))
    if ($sessionActive) { ecrireJournal "Session utilisateur active : les installations seront reportees." }

    foreach ($entree in $applications) {
        $nom = ("$entree" -replace '^ArtCraft\.', '').Trim()
        if ($nom -notmatch '^[A-Za-z0-9]+$') {
            ecrireJournal "Nom d'application invalide ignore : '$entree'"
            $echecs++
            continue
        }
        $depot = $nom.ToLowerInvariant()

        try {
            $tag = obtenirDernierTag $organisation $depot             $racineCache $ecriturePermise $ageMax $githubPermis
                        if (!$tag) {
                            ecrireJournal "$nom : aucune version connue dans le cache (telechargementGitHub = false), rien a faire."
                            continue
                        }
                        $derniereVersion = convertirEnVersion $tag
            if (!$derniereVersion) { throw "Tag illisible : $tag" }
            $versionInstallee = obtenirVersionInstallee $nom

            if ($versionInstallee -and $versionInstallee -ge $derniereVersion) {
                ecrireJournal "$nom $versionInstallee : a jour."
                completerCache $organisation $depot $tag $arch $racineCache $ecriturePermise $nombreAGarder $githubPermis
                continue
            }
            if (!$versionInstallee -and !$installerManquantes) {
                ecrireJournal "$nom : non installe (installerManquantes = false)."
                completerCache $organisation $depot $tag $arch $racineCache $ecriturePermise $nombreAGarder $githubPermis
                continue
            }

            $depart = if ($versionInstallee) { "$versionInstallee" } else { "non installe" }
            ecrireJournal "$nom : $depart -> $derniereVersion"
            if ($dryRun) { continue }

            # On alimente le cache meme si l'installation est reportee
            $msi = obtenirMsiVerifie $organisation $depot $tag $arch             $racineCache $ecriturePermise $nombreAGarder $githubPermis
                        if (!$msi) { continue }
                        if ($sessionActive) {
                ecrireJournal "$nom : installation reportee (session active)."
                continue
            }
            installerMsi $msi $nom
            Remove-Item (Split-Path $msi) -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            $echecs++
            ecrireJournal "ERREUR pour $nom : $($_.Exception.Message)"
        }
    }

    if ($supprimerRaccourcis) {
        $nomsRaccourcis = @($applications | ForEach-Object { ("$_" -replace '^ArtCraft\.', '').Trim() } | Where-Object { $_ -match '^[A-Za-z0-9]+$' })
        supprimerRaccourcisBureau $nomsRaccourcis ([bool]$dryRun)
    }

    Get-ChildItem $dossierJournaux -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    ecrireJournal "Termine ($echecs erreur(s))."
}
catch {
    $echecs++
    ecrireJournal "ERREUR FATALE : $($_.Exception.Message)"
}
finally {
    if ($possedeMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    Stop-Transcript | Out-Null
}

if ($echecs -gt 0) { exit 1 }
