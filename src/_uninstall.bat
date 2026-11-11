IF "%PROCESSOR_ARCHITEW6432%"=="" GOTO native
%SystemRoot%\Sysnative\cmd.exe /c %0 %*
exit
:native


REM ************** INSTALL/UNINSTALL **************
REM Retire la tache, desinstalle les applications ArtCraft de la config et supprime l'updater
REM (pour garder les applications : utiliser _uninstall-tache.bat)
START /WAIT "" powershell.exe -ExecutionPolicy Bypass -NoLogo -File "%~dp0Uninstall-ArtCraft.ps1"
exit /b %ERRORLEVEL%
