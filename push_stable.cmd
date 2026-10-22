@echo off
rem Pushes the local release branch (Stable, built by the kit's tools/wsl/stable.sh: kif-beta without dev files): every player with
rem Updates: Stable is offered it at their next start, and the installers download it.
rem It doesn't create a GitHub Releases entry (those are made by hand).
rem Test builds go out with push_branches.cmd (beta-testing = Beta channel).
setlocal
set GIT=git
where git >nul 2>nul || for /d %%d in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do set "GIT=%%d\resources\app\git\cmd\git.exe"
cd /d "%~dp0"
set /p VER=<Data\VERSION
echo.
echo This moves Stable to KIF %VER%: EVERY player on Stable is offered it, and new installs get it.
echo Push kif-beta first (push_branches.cmd) so GitHub has this exact version.
echo.
choice /M "Move Stable to KIF %VER%"
if errorlevel 2 (echo Cancelled. & pause & exit /b 0)
"%GIT%" push origin release
if errorlevel 1 (echo FAILED - push kif-beta with GitHub Desktop first, then try again. & pause & exit /b 1)
echo Done: Stable is KIF %VER%. Players get it at their next start.
pause
