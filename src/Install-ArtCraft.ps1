<#
.SYNOPSIS
    Deploie l'updater ArtCraft sur le poste : copie les fichiers, cree la tache planifiee (SYSTEM)
    et la demarre (c'est la tache qui installe ensuite les applications listees dans la configuration).
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

# Repetition toutes les heures, avec un decalage aleatoire pour etaler la charge sur le partage
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

# La tache fait l'installation initiale des applications
Start-ScheduledTask -TaskName $nomTache
Write-Host "Tache '$nomTache' demarree."
