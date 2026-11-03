@echo off
rem KIF: publish a mod to the community catalog (cody-png/kif-discord-mods)
rem through your own GitHub account and the GitHub CLI (gh).
rem Options, Mods, Publish a mod starts this; you can run it yourself too:
rem
rem   publish_mod.bat "<mod folder>" "<catalog folder name>" "<branch>" "<commit message file>" "<pull request body file>" "<mod id>"
rem
rem Catalog contributors (write access) publish straight to main: only their
rem own mod's folder. A folder's owners are the logins on its line in the
rem catalog's owners.txt ("folder: login login", changed only by a reviewed
rem commit); with no line, the account that added the folder or last changed it.
rem Everyone else (and a contributor who isn't the owner) gets a pull request
rem from their fork, reviewed before it goes live.
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

rem 3. Contributors push to the catalog (step 5 may still send them to their fork); everyone else to their fork
set "PUSH="
for /f "usebackq delims=" %%a in (`gh api repos/%UPSTREAM% --jq .permissions.push 2^>nul`) do set "PUSH=%%a"
if /i "!PUSH!"=="true" (
  set "DIRECT=1"
  set "TARGET=%UPSTREAM%"
  echo You're a contributor to the catalog: your own mods are published straight away.
) else (
  set "DIRECT=0"
  call :use_fork || goto :fail
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

rem 5. Contributors change only their own mod: the folder's owners (see :owner)
set "HAS="
for /f "usebackq delims=" %%a in (`git ls-tree --name-only upstream/main -- "!FOLDER!"`) do set "HAS=1"
if defined HAS (
  set "ISDIR="
  for /f "usebackq delims=" %%a in (`git ls-tree -d --name-only upstream/main -- "!FOLDER!"`) do set "ISDIR=1"
  if not defined ISDIR (set "WHY=!FOLDER! is a file in the catalog, not a mod folder." & goto :fail)
)
if "!DIRECT!"=="1" call :owner || goto :fail
if "!DIRECT!"=="1" call :guard_id || goto :fail

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
set /a PTRIES=0
:push_try
git push -q -f origin "!BRANCH!" && goto :pushed
set /a PTRIES+=1
if !PTRIES! geq 4 (set "WHY=couldn't upload to !TARGET!." & goto :fail)
echo Waiting for GitHub to finish your copy...
ping -n 6 127.0.0.1 >nul
goto :push_try
:pushed
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

rem The owners are the logins on the folder's line in owners.txt (the catalog's
rem maintainer sets it, so editing the mod on GitHub never changes it); with no
rem line, the account that added the folder or last changed it. Anyone else goes
rem the pull request way. owners.txt is read from the catalog's main, not from
rem the working copy; each line is  folder: login login
:owner
set "ENTRY="
set "OWNERS="
for /f "usebackq tokens=1* delims=:" %%k in (`git show upstream/main:owners.txt 2^>nul`) do (
  set "K=%%k"
  call :trim_key
  if /i "!K!"=="!FOLDER!" if not defined ENTRY (set "ENTRY=1" & set "OWNERS=%%l")
)
if not defined HAS if not defined ENTRY exit /b 0
set "MINE="
set "SHA="
for /f "usebackq delims=" %%a in (`git log -1 "--format=%%H" upstream/main -- "!FOLDER!"`) do set "SHA=%%a"
call :author_of
set "LAST_BY=!BY!"
if defined ENTRY goto :owner_listed
set "SHA="
for /f "usebackq delims=" %%a in (`git log --diff-filter=A "--format=%%H" upstream/main -- "!FOLDER!"`) do set "SHA=%%a"
call :author_of
set "FIRST_BY=!BY!"
if /i "!FIRST_BY!"=="!LOGIN!" set "MINE=1"
if /i "!LAST_BY!"=="!LOGIN!" set "MINE=1"
set "NAMES=!FIRST_BY!"
if not defined NAMES set "NAMES=someone else"
set "WHYNOT=The catalog's owners.txt has no line for !FOLDER!, so the account that added the folder counts as its owner."
goto :owner_decide
:owner_listed
set "NAMES="
rem (the commas are taken out first: a comma inside the for list would split the variable name)
set "OWNERS=!OWNERS:,= !"
for %%o in (!OWNERS!) do (
  if /i "%%o"=="!LOGIN!" set "MINE=1"
  if defined NAMES (set "NAMES=!NAMES!, %%o") else set "NAMES=%%o"
)
if not defined NAMES set "NAMES=nobody"
set "WHYNOT=owners.txt in the catalog lists who may publish !FOLDER! straight away."
:owner_decide
rem the catalog's own account can't fork its own repository, and it can push anywhere
for /f "delims=/" %%u in ("%UPSTREAM%") do if /i "%%u"=="!LOGIN!" set "MINE=1"
if defined MINE goto :owner_mine
echo.
echo This mod's owner on the catalog is !NAMES!; you are signed in as !LOGIN!.
echo !WHYNOT!
echo To publish updates to it straight away, ask the catalog's maintainer to add you as an owner of !FOLDER! in owners.txt.
echo For now it goes as a pull request, which is reviewed before it goes live.
set "DIRECT=0"
call :use_fork || exit /b 1
set "ORIGIN=!GITHUB!/!TARGET!.git"
git remote set-url origin "!ORIGIN!"
exit /b 0
:owner_mine
if not defined HAS exit /b 0
if /i "!LAST_BY!"=="!LOGIN!" exit /b 0
set "WHO=!LAST_BY!"
if not defined WHO set "WHO=someone else"
echo.
echo Note: the catalog's !FOLDER! folder was last changed by !WHO!, not you. Publishing replaces it with your files, so a change made on GitHub is lost unless your folder has it too. Check the list below.
exit /b 0

rem a line's folder name without the spaces around it
:trim_key
for /f "tokens=* delims= " %%t in ("!K!") do set "K=%%t"
:trim_key_end
if "!K:~-1!"==" " (set "K=!K:~0,-1!" & goto :trim_key_end)
exit /b 0

rem the GitHub account behind commit !SHA! into BY; else yours, when the commit has your address
:author_of
set "BY="
if not defined SHA exit /b 0
for /f "usebackq delims=" %%a in (`gh api repos/%UPSTREAM%/commits/!SHA! --jq .author.login 2^>nul`) do set "BY=%%a"
if "!BY!"=="null" set "BY="
if defined BY exit /b 0
set "ADDR="
for /f "usebackq delims=" %%a in (`git log -1 "--format=%%ae" !SHA!`) do set "ADDR=%%a"
if /i "!ADDR!"=="!EMAIL!" set "BY=!LOGIN!"
if /i "!ADDR!"=="!LOGIN!@users.noreply.github.com" set "BY=!LOGIN!"
exit /b 0

:use_fork
echo Making your own copy - a fork - of %UPSTREAM%, if you don't have one yet...
gh repo fork %UPSTREAM% --clone=false >nul 2>nul || (set "WHY=couldn't fork %UPSTREAM%." & exit /b 1)
rem shortcut: assumes the fork kept the name kif-discord-mods; a renamed fork needs KIF_PUBLISH_CACHE pointed at a clone of it
set "TARGET=!LOGIN!/kif-discord-mods"
exit /b 0

rem an id no other folder uses; anything else is for the catalog's owner
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
