@echo off
rem Pushes kif-beta and beta-testing to GitHub without checking either out,
rem so the working folder (and the CodyDebug file) is never touched.
rem First run may open a browser window to sign in to GitHub; that is normal.
setlocal
set GIT=git
where git >nul 2>nul || for /d %%d in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do set "GIT=%%d\resources\app\git\cmd\git.exe"
cd /d "%~dp0"
echo Pushing kif-beta and beta-testing ...
"%GIT%" push origin kif-beta beta-testing
if errorlevel 1 (echo FAILED - open GitHub Desktop once and push from there, then try again. & pause & exit /b 1)
echo Done.
"%GIT%" log --oneline -1 kif-beta
"%GIT%" log --oneline -1 beta-testing
pause
