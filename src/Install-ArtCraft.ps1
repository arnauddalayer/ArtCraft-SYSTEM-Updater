<#
.SYNOPSIS
    Déploie l'updater ArtCraft sur le poste : copie les fichiers, crée la tâche planifiée (SYSTEM)
    et la démarre (c'est la tâche qui installe ensuite les applications listées dans la configuration).
#>
$ErrorActionPreference = "Stop"

$dossierInstallation = Join-Path $env:ProgramData "ArtCraft-SYSTEM-Updater"
$nomTache = "ArtCraft-SYSTEM-Updater"
$intervalleHeures = 1

if (!(Test-Path $dossierInstallation)) {
    New-Item -ItemType Directory -Path $dossierInstallation -Force | Out-Null
}

Copy-Item (Join-Path $PSScriptRoot "Update-ArtCraft.ps1") $dossierInstallation -Force
$sourceConfig = Join-Path $PSScriptRoot "Update-ArtCraft.json"
if (!(Test-Path $sourceConfig)) { $sourceConfig = Join-Path $PSScriptRoot "Update-ArtCraft.example.json" }
Copy-Item $sourceConfig (Join-Path $dossierInstallation "Update-ArtCraft.json") -Force

Unregister-ScheduledTask -TaskName $nomTache -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -NonInteractive -File `"$dossierInstallation\Update-ArtCraft.ps1`""

# Répétition toutes les heures, avec un décalage aléatoire pour étaler la charge sur le partage
$declencheur = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Hours $intervalleHeures) `
    -RandomDelay (New-TimeSpan -Minutes 10)

$parametres = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

$principal = New-ScheduledTaskPrincipal `
    -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $nomTache `
    -Action $action `
    -Trigger $declencheur `
    -Settings $parametres `
    -Principal $principal | Out-Null

Write-Host "Tache '$nomTache' creee."

# La tâche fait l'installation initiale des applications
Start-ScheduledTask -TaskName $nomTache
Write-Host "Tache '$nomTache' demarree."
