<#
.SYNOPSIS
    Désinstalle l'updater ArtCraft : supprime la tâche planifiée, désinstalle les applications
    listées dans la configuration (MSI systemwide) et supprime C:\ProgramData\ArtCraft-SYSTEM-Updater.

.PARAMETER conserverApplications
    Ne désinstalle pas les applications, retire seulement la tâche planifiée et les fichiers de l'updater.
#>
[CmdletBinding()]
param(
    [switch]$conserverApplications
)

$ErrorActionPreference = "Continue"

$dossierInstallation = Join-Path $env:ProgramData "ArtCraft-SYSTEM-Updater"
$nomTache = "ArtCraft-SYSTEM-Updater"
$echecs = 0

# Évite qu'une mise à jour en cours installe une application pendant la désinstallation
$mutex = New-Object System.Threading.Mutex($false, "Global\ArtCraftSystemUpdater")
if (!$mutex.WaitOne(120000)) {
    Write-Host "Une mise a jour est en cours depuis plus de 2 minutes, desinstallation annulee."
    exit 1
}

try {
    Write-Host "=== Desinstallation ArtCraft ==="

    if (Get-ScheduledTask -TaskName $nomTache -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $nomTache -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $nomTache -Confirm:$false
        Write-Host "Tache '$nomTache' supprimee."
    }
    else { Write-Host "Tache '$nomTache' absente." }

    if (!$conserverApplications) {
        $cheminConfig = Join-Path $dossierInstallation "Update-ArtCraft.json"
        if (!(Test-Path $cheminConfig)) { $cheminConfig = Join-Path $PSScriptRoot "Update-ArtCraft.json" }

        $applications = @()
        try { $applications = @((Get-Content $cheminConfig -Raw | ConvertFrom-Json).applications) }
        catch { Write-Host "Configuration illisible ($cheminConfig) : aucune application desinstallee." ; $echecs++ }

        $cles = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $installees = Get-ItemProperty -Path $cles -ErrorAction SilentlyContinue

        foreach ($entree in $applications) {
            $nom = ("$entree" -replace '^ArtCraft\.', '').Trim()
            $produits = @($installees | Where-Object { $_.DisplayName -ieq $nom -and $_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$' })
            if ($produits.Count -eq 0) {
                Write-Host "$nom : non installe (MSI)."
                continue
            }
            foreach ($produit in $produits) {
                Write-Host "Desinstallation de $nom $($produit.DisplayVersion)..."
                $journal = Join-Path $env:TEMP ("msi-desinstallation-{0}.log" -f $nom)
                $processus = Start-Process msiexec.exe -ArgumentList "/x $($produit.PSChildName) /qn /norestart /l*v `"$journal`"" -Wait -PassThru
                if ($processus.ExitCode -in 0, 1605, 3010, 1641) { Write-Host "$nom desinstalle (code $($processus.ExitCode))." }
                else { Write-Host "ERREUR : msiexec a retourne $($processus.ExitCode) pour $nom (voir $journal)." ; $echecs++ }
            }
        }
    }

    if (Test-Path $dossierInstallation) {
        Remove-Item $dossierInstallation -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $dossierInstallation) { Write-Host "Certains fichiers de $dossierInstallation n'ont pas pu etre supprimes." }
        else { Write-Host "Dossier $dossierInstallation supprime." }
    }

    Write-Host "Termine ($echecs erreur(s))."
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

if ($echecs -gt 0) { exit 1 }
