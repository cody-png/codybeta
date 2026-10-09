@echo off
rem Builds a clean KIF Beta zip from the committed files of a branch (nothing
rem from your working folder: no saves, logs, mods, scratch, .git).
rem   build_release.cmd [branch] [version]     e.g. build_release.cmd beta-testing 0.21.0
setlocal
set BRANCH=%1
if "%BRANCH%"=="" set BRANCH=beta-testing
set VER=%2
if "%VER%"=="" set VER=%date:~-4%%date:~-7,2%%date:~-10,2%
set GIT=git
where git >nul 2>nul || for /d %%d in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do set "GIT=%%d\resources\app\git\cmd\git.exe"
set OUT=..\Releases
if not exist "%OUT%" mkdir "%OUT%"
set ZIP=%OUT%\KIF-Beta-%VER%-%BRANCH%.zip
echo Building %ZIP% from branch %BRANCH% ...
"%GIT%" archive --format=zip -0 -o "%ZIP%" --prefix="KIF Beta/" %BRANCH%
if errorlevel 1 (echo FAILED & pause & exit /b 1)
echo Done: %ZIP%
echo Attach it to a GitHub Release (Releases - Draft a new release), together with the sprite pack link.
pause
