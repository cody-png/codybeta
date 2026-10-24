@echo off
rem KIF: publish a mod to the community catalog (cody-png/kif-discord-mods)
rem through your own GitHub account and the GitHub CLI (gh).
rem Options, Mods, Publish a mod starts this; you can run it yourself too:
rem
rem   publish_mod.bat "<mod folder>" "<catalog folder name>" "<branch>" "<commit message file>" "<pull request body file>" "<mod id>"
rem
rem Catalog contributors (write access) publish straight to main: only their
rem own mod's folder, and only a folder they last changed themselves. Everyone
rem else gets a pull request from their fork, reviewed before it goes live.
rem The message file's first line is the commit's and pull request's title.
rem KIF never sees your GitHub sign-in: gh keeps it.
rem   KIF_PUBLISH_DRY=1     stop before anything is pushed (shows what would happen)
rem   KIF_PUBLISH_CACHE     where the copy of the catalog is kept
rem   KIF_PUBLISH_GITHUB    GitHub's address for git (only changed for testing)

rem the arguments are read before delayed expansion is on, so a ! in a path stays
setlocal DisableDelayedExpansion
set "MODDIR=%~1"
set "FOLDER=%~2"
set "BRANCH=%~3"
set "MSGFILE=%~4"
set "BODYFILE=%~5"
set "ID=%~6"
set "UPSTREAM=cody-png/kif-discord-mods"
set "GITHUB=https://github.com"
if defined KIF_PUBLISH_GITHUB set "GITHUB=%KIF_PUBLISH_GITHUB%"
set "CACHE=%LOCALAPPDATA%\KIF\publish\kif-discord-mods"
if defined KIF_PUBLISH_CACHE set "CACHE=%KIF_PUBLISH_CACHE%"
rem regex pieces for "id": "<id>" in a mod.json (set here: carets stay as typed)
set "ID_BEFORE=[^a-z0-9_]id.[[:space:]]*:[[:space:]]*."
set "ID_AFTER=[^a-z0-9_-]"
setlocal EnableDelayedExpansion
chcp 65001 >nul
title Publish a KIF mod
echo Publish a KIF mod
echo =================

if "!MODDIR:~-1!"=="\" set "MODDIR=!MODDIR:~0,-1!"
set "WHY=there's no mod.json in the mod folder. Start this from the game: Options, Mods, Publish a mod."
if not exist "!MODDIR!\mod.json" goto :fail
set "WHY=the message files from the game are missing. Start this from the game."
if not exist "!MSGFILE!" goto :fail
if not exist "!BODYFILE!" goto :fail
set "WHY=the catalog folder name is missing or not allowed."
if "!FOLDER!"=="" goto :fail
if "!FOLDER:~0,1!"=="." goto :fail
if not "!FOLDER:..=!"=="!FOLDER!" goto :fail
if not "!FOLDER:\=!"=="!FOLDER!" goto :fail
if not "!FOLDER:/=!"=="!FOLDER!" goto :fail
set "WHY=the branch name must start with mod/."
if not "!BRANCH:~0,4!"=="mod/" goto :fail
set "WHY=the mod id may only have a-z, 0-9, _ and -."
if "!ID!"=="" goto :fail
rem anything left after taking out the allowed characters is not allowed
for /f "delims=abcdefghijklmnopqrstuvwxyz0123456789_-" %%c in ("!ID!") do goto :fail

rem 1. Git and the GitHub CLI
where git >nul 2>nul || call :install Git.Git git "Git" "https://git-scm.com/download/win" "%ProgramFiles%\Git\cmd"
set "WHY=Git is needed."
where git >nul 2>nul || goto :fail
where gh >nul 2>nul || call :install GitHub.cli gh "The GitHub CLI" "https://cli.github.com" "%ProgramFiles%\GitHub CLI"
set "WHY=the GitHub CLI is needed."
where gh >nul 2>nul || goto :fail

rem 2. Sign in (once; gh remembers it)
gh auth status >nul 2>nul
if errorlevel 1 (
  echo.
  echo Sign in to GitHub: a code is shown here, then your browser opens. Enter the code there.
  gh auth login --web --hostname github.com --git-protocol https
  if errorlevel 1 (set "WHY=GitHub sign-in didn't finish." & goto :fail)
)
set "LOGIN="
set "UID_="
for /f "usebackq delims=" %%a in (`gh api user --jq .login`) do set "LOGIN=%%a"
for /f "usebackq delims=" %%a in (`gh api user --jq .id`) do set "UID_=%%a"
set "WHY=couldn't read your GitHub user name."
if not defined LOGIN goto :fail
if not defined UID_ goto :fail
rem GitHub's private address for the account: commits count as yours, your own email stays private
set "EMAIL=!UID_!+!LOGIN!@users.noreply.github.com"
echo Signed in as !LOGIN!.

rem 3. Contributors push to the catalog; everyone else to their fork
set "PUSH="
for /f "usebackq delims=" %%a in (`gh api repos/%UPSTREAM% --jq .permissions.push 2^>nul`) do set "PUSH=%%a"
if /i "!PUSH!"=="true" (
  set "DIRECT=1"
  set "TARGET=%UPSTREAM%"
  echo You're a contributor to the catalog: the mod is published straight away.
) else (
  set "DIRECT=0"
  echo Making your own copy - a fork - of %UPSTREAM%, if you don't have one yet...
  gh repo fork %UPSTREAM% --clone=false >nul 2>nul || (set "WHY=couldn't fork %UPSTREAM%." & goto :fail)
  rem shortcut: assumes the fork kept the name kif-discord-mods; a renamed fork needs KIF_PUBLISH_CACHE pointed at a clone of it
  set "TARGET=!LOGIN!/kif-discord-mods"
)

rem 4. A copy of the catalog on this computer, on a new branch from the catalog's main
set "ORIGIN=!GITHUB!/!TARGET!.git"
if exist "!CACHE!\.git" goto :have_clone
if exist "!CACHE!" rmdir /s /q "!CACHE!"
mkdir "!CACHE!" || (set "WHY=can't make the folder !CACHE!." & goto :fail)
set /a TRIES=0
:clone
git -c core.autocrlf=false clone -q "!ORIGIN!" "!CACHE!" && goto :have_clone
set /a TRIES+=1
if !TRIES! geq 4 (set "WHY=couldn't download !TARGET!." & goto :fail)
echo Waiting for GitHub to finish your copy...
ping -n 6 127.0.0.1 >nul
goto :clone
:have_clone
cd /d "!CACHE!" || (set "WHY=can't open !CACHE!." & goto :fail)
git remote set-url origin "!ORIGIN!"
git remote remove upstream >nul 2>nul
git remote add upstream "!GITHUB!/%UPSTREAM%.git"
rem pushes sign in through gh, in this copy only (your git settings stay as they are)
setlocal DisableDelayedExpansion
git config --local --unset-all credential.helper
git config --local --add credential.helper ""
git config --local --add credential.helper "!gh auth git-credential"
git config --local core.quotepath off
rem the mod's files go up byte for byte, as the game checked them
git config --local core.autocrlf false
endlocal
git fetch -q upstream main || (set "WHY=couldn't read %UPSTREAM%." & goto :fail)
git checkout -q -f -B "!BRANCH!" upstream/main || (set "WHY=couldn't make the branch !BRANCH!." & goto :fail)
git clean -q -fdx

rem 5. Contributors change only their own mod
if "!DIRECT!"=="1" call :guard || goto :fail

rem 6. The mod's files (not its .git folder or KIF's install lists)
if exist "!FOLDER!" rmdir /s /q "!FOLDER!"
robocopy "!MODDIR!" "!CACHE!\!FOLDER!" /E /XD .git /XF .kif_installed .installed_assets /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (set "WHY=couldn't copy the mod's files." & goto :fail)
git add -A -- "!FOLDER!"
git diff --cached --quiet && (echo. & echo Nothing to upload: the catalog already has exactly these files. & goto :done)
git -c "user.name=!LOGIN!" -c "user.email=!EMAIL!" commit -q --cleanup=verbatim -F "!MSGFILE!" || (set "WHY=couldn't save the change - git commit." & goto :fail)
git diff --name-only upstream/main HEAD > "!CACHE!\.git\kif_changed.txt"
set "WHY=the change would touch files outside the mod's folder."
findstr /v /b /l /c:"!FOLDER!/" "!CACHE!\.git\kif_changed.txt" && goto :fail
echo Files ready:
git --no-pager show --stat --format= HEAD

if not "%KIF_PUBLISH_DRY%"=="1" goto :push
echo.
if "!DIRECT!"=="1" (echo Dry run: would publish !FOLDER! straight to %UPSTREAM% main.) else (echo Dry run: would push !BRANCH! to !TARGET! and open a pull request to %UPSTREAM%.)
goto :done

:push
if not "!DIRECT!"=="1" goto :push_fork
rem 7a. Contributors: straight to main
git push -q origin "HEAD:main" || (set "WHY=couldn't publish: the catalog changed while this ran. Run it again." & goto :fail)
echo.
echo Published: players get it at their next catalog check.
echo The catalog's check runs on every change; a red X here means something needs fixing:
echo   https://github.com/%UPSTREAM%/commits/main
goto :done

:push_fork
rem 7b. Everyone else: the fork's branch, then the pull request (an open one
rem for this branch is updated by the push)
git fetch -q origin "+refs/heads/!BRANCH!:refs/remotes/origin/!BRANCH!" 2>nul && git diff --quiet "origin/!BRANCH!" HEAD -- "!FOLDER!" && (echo. & echo Nothing to upload: your pull request already has exactly these files. & goto :done)
git push -q -f origin "!BRANCH!" || (set "WHY=couldn't upload to !TARGET!." & goto :fail)
call :find_pr
if defined URL goto :have_pr
set "TITLE="
rem the first line (the game leaves " and ! out of it: a command line here would change them)
for /f "usebackq delims=" %%t in ("!MSGFILE!") do if not defined TITLE set "TITLE=%%t"
gh pr create --repo %UPSTREAM% --base main --head "!LOGIN!:!BRANCH!" --title "!TITLE!" --body-file "!BODYFILE!" >nul || (set "WHY=couldn't open the pull request." & goto :fail)
call :find_pr
goto :show_pr
:have_pr
echo Your open pull request is updated.
:show_pr
echo.
echo Pull request: !URL!
echo The catalog's check runs there within a few minutes, then the mod is reviewed. Fix anything the check reports and publish again.
if defined URL gh pr view "!URL!" --repo %UPSTREAM% --web >nul 2>nul

:done
echo.
if not defined KIF_PUBLISH_NO_PAUSE pause
exit /b 0

:fail
echo.
echo Stopped: !WHY!
echo Nothing was published unless a link was shown above.
echo.
if not defined KIF_PUBLISH_NO_PAUSE pause
exit /b 1

rem the open pull request from this branch, or none
:find_pr
set "URL="
for /f "usebackq delims=" %%u in (`gh pr list --repo %UPSTREAM% --head "!BRANCH!" --state open --author "!LOGIN!" --json url --jq ".[].url"`) do if not defined URL set "URL=%%u"
exit /b 0

rem A contributor may change a folder they last changed themselves, with an id
rem no other folder uses; anything else is for the catalog's owner
:guard
set "HAS="
for /f "usebackq delims=" %%a in (`git ls-tree -d --name-only upstream/main -- "!FOLDER!"`) do set "HAS=1"
if not defined HAS goto :guard_id
set "QF=!FOLDER: =%%20!"
set "OWNER="
for /f "usebackq delims=" %%a in (`gh api "repos/%UPSTREAM%/commits?path=!QF!&sha=main&per_page=1" --jq ".[0].author.login" 2^>nul`) do set "OWNER=%%a"
if "!OWNER!"=="null" set "OWNER="
if defined OWNER goto :guard_owner
rem an address GitHub doesn't link to an account: compare the address
set "LAST="
for /f "usebackq delims=" %%a in (`git log -1 "--format=%%ae" upstream/main -- "!FOLDER!"`) do set "LAST=%%a"
if /i "!LAST!"=="!EMAIL!" set "OWNER=!LOGIN!"
if /i "!LAST!"=="!LOGIN!@users.noreply.github.com" set "OWNER=!LOGIN!"
:guard_owner
if /i "!OWNER!"=="!LOGIN!" goto :guard_id
if not defined OWNER set "OWNER=someone else"
set "WHY=the catalog's !FOLDER! folder was last changed by !OWNER!, not you. To change another modder's mod, ask Cody on the KIF Discord."
exit /b 1
:guard_id
rem shortcut: a text search, so an "id" inside another mod's dependency list also stops it (the safe side)
set "OTHER="
for /f "usebackq tokens=2 delims=:" %%a in (`git grep -l -E "!ID_BEFORE!!ID!!ID_AFTER!" upstream/main -- "*/mod.json"`) do (
  for /f "delims=/" %%b in ("%%a") do if not "%%b"=="!FOLDER!" if not defined OTHER set "OTHER=%%b"
)
if not defined OTHER exit /b 0
set "WHY=the id !ID! is already used by the catalog's !OTHER! folder. Ask Cody on the KIF Discord."
exit /b 1

rem :install <winget id> <command> <name> <download page> <folder it installs to>
:install
echo.
echo %~3 isn't installed. It's needed to upload your mod.
where winget >nul 2>nul || (echo Install it from %~4 and run this again. & exit /b 1)
choice /c YN /m "Install %~3 now with winget"
if errorlevel 2 exit /b 1
winget install --id %~1 -e --source winget
rem winget doesn't add it to this window's PATH
set "PATH=!PATH!;%~5"
where %~2 >nul 2>nul && exit /b 0
echo %~3 was installed. Close this window and choose Publish a mod in the game again.
exit /b 1
