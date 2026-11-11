IF "%PROCESSOR_ARCHITEW6432%"=="" GOTO native
%SystemRoot%\Sysnative\cmd.exe /c %0 %*
exit
:native


REM ************** UNINSTALL (tache et updater seulement) **************
REM Retire la tache planifiee et C:\ProgramData\ArtCraft-SYSTEM-Updater ; les applications ArtCraft sont conservees
START /WAIT "" powershell.exe -ExecutionPolicy Bypass -NoLogo -File "%~dp0Uninstall-ArtCraft.ps1" -conserverApplications
exit /b %ERRORLEVEL%
