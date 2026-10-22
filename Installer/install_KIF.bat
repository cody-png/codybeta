@echo off
setlocal EnableExtensions
title KIF installer
rem ==========================================================================
rem  KIF installer for Windows 10 / 11
rem  Put this file in the folder you want and double-click it. It makes a
rem  "KIF" folder next to itself, downloads the game from GitHub into it and
rem  unpacks it. After that the game keeps itself up to date (in-game updater).
rem  Saves live in %APPDATA%\KIF and are never touched by this installer.
rem  Needs about 4.5 GB free while installing (2 GB once done).
rem ==========================================================================
set "REPO=https://github.com/cody-png/codybeta/archive/refs/heads"
set "HERE=%~dp0"
set "TARGET=%HERE%KIF"
set "ZIP=%TARGET%\KIF_download.zip"
set "CURL=%SystemRoot%\System32\curl.exe"
set "TAR=%SystemRoot%\System32\tar.exe"
set "TAGS=https://github.com/cody-png/codybeta/archive/refs/tags"
rem  PIN: the version a release's installer belongs to (set when a release is
rem  published, e.g. 1.1.0); empty = only Stable / Beta are offered.
set "PIN="

echo.
echo  ===================================
echo    KIF installer
echo  ===================================
echo.
echo  The game will be installed into:
echo    %TARGET%
echo.

if not exist "%CURL%" goto :no_tools
if not exist "%TAR%" goto :no_tools

if exist "%TARGET%\InfiniteFusion.exe" (
  echo  KIF is already installed there.
  echo  Reinstalling downloads the game again and puts back any missing or
  echo  damaged game files. Your saves, mods and imported sprites are kept.
  echo  ^(To just update, start the game: it updates itself.^)
  echo.
  choice /C RC /N /M "  [R] Reinstall   [C] Cancel : "
  if errorlevel 2 goto :cancel
  echo.
)

echo  Which version?
echo    [S] Stable - the newest released version, keeps itself updated (recommended)
echo    [B] Beta   - test builds: newest features, may have bugs
if defined PIN echo    [V] KIF %PIN% only - stays on this version, no updates
echo.
if defined PIN (
  choice /C SBV /N /M "  Choose S, B or V : "
) else (
  choice /C SB /N /M "  Choose S or B : "
)
set "PICK=%errorlevel%"
set "BRANCH=release"
set "URL=%REPO%/release.zip"
if "%PICK%"=="2" set "BRANCH=beta-testing"
if "%PICK%"=="2" set "URL=%REPO%/beta-testing.zip"
if "%PICK%"=="3" set "BRANCH=%PIN%"
if "%PICK%"=="3" set "URL=%TAGS%/%PIN%.zip"
echo.

if not exist "%TARGET%" mkdir "%TARGET%" 2>nul
if not exist "%TARGET%" (
  echo  Couldn't make the folder "%TARGET%".
  echo  Move this installer to a folder you can write to ^(e.g. Documents or a game drive^).
  goto :end_fail
)

echo  Downloading KIF ^(%BRANCH%^) - about 1.9 GB, this takes a while...
echo.
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
"%CURL%" -L --fail --retry 5 --retry-delay 3 -o "%ZIP%" "%URL%"
if errorlevel 1 goto :download_failed

echo.
echo  Unpacking ^(a few minutes - about 30,000 files^)...
"%TAR%" -xf "%ZIP%" -C "%TARGET%" --strip-components=1
if errorlevel 1 goto :unpack_failed
del /f /q "%ZIP%" >nul 2>&1

if not exist "%TARGET%\InfiniteFusion.exe" goto :unpack_failed
rem  a fixed version: the game skips its automatic update check (KIF_pinned.txt)
if "%PICK%"=="3" (> "%TARGET%\KIF_pinned.txt" echo %PIN%) else (if exist "%TARGET%\KIF_pinned.txt" del /f /q "%TARGET%\KIF_pinned.txt" >nul 2>&1)

echo.
echo  ===================================
echo    KIF is installed!
echo  ===================================
echo.
echo  Start it with "InfiniteFusion.exe" in the KIF folder.
echo  Sprite pack: put the PIF sprite pack .zip into the "Import Sprites"
echo  folder inside KIF; the game installs it the next time it starts.
echo.
choice /C YN /N /M "  Start KIF now? [Y/N] : "
if errorlevel 2 goto :done
start "" /D "%TARGET%" "%TARGET%\InfiniteFusion.exe"
goto :done

:download_failed
echo.
if /I "%BRANCH%"=="release" (
  echo  The download failed. If this keeps happening there may be no Stable
  echo  release yet - run the installer again and choose [B] Beta.
) else (
  echo  The download failed. Check your internet connection and run the
  echo  installer again.
)
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
goto :end_fail

:unpack_failed
echo.
echo  Unpacking failed ^(not enough disk space, or the download was cut short^).
echo  Free some space and run the installer again.
if exist "%ZIP%" del /f /q "%ZIP%" >nul 2>&1
goto :end_fail

:no_tools
echo  This installer needs Windows 10 ^(version 1803 or newer^) or Windows 11.
echo  On older Windows, download the game zip from the GitHub releases page instead.
goto :end_fail

:cancel
echo  Nothing was changed.
goto :done

:end_fail
echo.
pause
exit /b 1

:done
echo.
pause
exit /b 0
