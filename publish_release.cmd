@echo off
rem Makes the current kif-beta the STABLE release: every player with
rem Updates: Stable is offered it at their next start (KIF updater, C-SYS-06).
rem Test builds go out with push_branches.cmd (beta-testing = Beta channel).
setlocal
set GIT=git
where git >nul 2>nul || for /d %%d in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do set "GIT=%%d\resources\app\git\cmd\git.exe"
cd /d "%~dp0"
set /p VER=<Data\VERSION
echo.
echo This publishes kif-beta (KIF Beta %VER%) to EVERY player on the Stable channel.
echo Push kif-beta first (push_branches.cmd) so GitHub has this exact version.
echo.
choice /M "Publish KIF Beta %VER% as the stable release"
if errorlevel 2 (echo Cancelled. & pause & exit /b 0)
"%GIT%" push origin kif-beta:release
if errorlevel 1 (echo FAILED - push kif-beta with GitHub Desktop first, then try again. & pause & exit /b 1)
echo Done: players get %VER% at their next start.
pause
