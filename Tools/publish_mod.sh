#!/usr/bin/env bash
# KIF: publish a mod to the community catalog (cody-png/kif-discord-mods)
# through your own GitHub account and the GitHub CLI (gh).
# Options > Mods > Publish a mod starts this; you can run it yourself too:
#
#   bash publish_mod.sh <mod folder> <catalog folder name> <branch> <commit message file> <pull request body file> <mod id>
#
# Catalog contributors (write access) publish straight to main: only their
# own mod's folder, and only a folder they last changed themselves. Everyone
# else gets a pull request from their fork, reviewed before it goes live.
# The message file's first line is the commit's and pull request's title.
# KIF never sees your GitHub sign-in: gh keeps it.
#   KIF_PUBLISH_DRY=1     stop before anything is pushed (shows what would happen)
#   KIF_PUBLISH_CACHE     where the copy of the catalog is kept
#   KIF_PUBLISH_GITHUB    GitHub's address for git (only changed for testing)
set -u

MODDIR="${1:-}"; FOLDER="${2:-}"; BRANCH="${3:-}"; MSGFILE="${4:-}"; BODYFILE="${5:-}"; ID="${6:-}"
UPSTREAM="cody-png/kif-discord-mods"
GITHUB="${KIF_PUBLISH_GITHUB:-https://github.com}"
CACHE="${KIF_PUBLISH_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/kif/publish/kif-discord-mods}"

finish() {
  echo
  [ -n "${KIF_PUBLISH_NO_PAUSE:-}" ] || read -r -p "Press Enter to close this window." _ || true
  exit "$1"
}
fail() {
  echo
  echo "Stopped: $1"
  echo "Nothing was published unless a link was shown above."
  finish 1
}

echo "Publish a KIF mod"
echo "================="
MODDIR="${MODDIR%/}"
[ -f "$MODDIR/mod.json" ] || fail "no mod.json in \"$MODDIR\". Start this from the game (Options > Mods > Publish a mod)."
[ -f "$MSGFILE" ] && [ -f "$BODYFILE" ] || fail "the message files from the game are missing. Start this from the game."
case "$FOLDER" in ""|*/*|*\\*|*..*|.*) fail "\"$FOLDER\" can't be a catalog folder name." ;; esac
case "$BRANCH" in mod/*) ;; *) fail "\"$BRANCH\" isn't a mod/ branch." ;; esac
[[ "$ID" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || fail "\"$ID\" isn't a mod id (a-z, 0-9, _ and -)."

# 1. Git and the GitHub CLI
for tool in git gh; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo
    if [ "$tool" = git ]; then echo "Git isn't installed. Install it (for example: sudo apt install git) and run this again."
    else echo "The GitHub CLI (gh) isn't installed. Install it from https://cli.github.com and run this again."; fi
    if command -v brew >/dev/null 2>&1; then
      read -r -p "Install $tool now with Homebrew? [y/N] " yn
      case "$yn" in [yY]*) brew install "$tool" || fail "Homebrew couldn't install $tool." ;; *) finish 1 ;; esac
    else
      finish 1
    fi
  fi
done

# 2. Sign in (once; gh remembers it)
if ! gh auth status >/dev/null 2>&1; then
  echo
  echo "Sign in to GitHub: a code is shown here, then your browser opens. Enter the code there."
  gh auth login --web --hostname github.com --git-protocol https || fail "GitHub sign-in didn't finish."
fi
LOGIN="$(gh api user --jq .login)" || fail "couldn't read your GitHub user name."
UID_="$(gh api user --jq .id)" || fail "couldn't read your GitHub user name."
[ -n "$LOGIN" ] && [ -n "$UID_" ] || fail "couldn't read your GitHub user name."
# GitHub's private address for the account: commits count as yours, your own email stays private
EMAIL="$UID_+$LOGIN@users.noreply.github.com"
echo "Signed in as $LOGIN."

# 3. Contributors push to the catalog; everyone else to their fork
if [ "$(gh api "repos/$UPSTREAM" --jq .permissions.push 2>/dev/null)" = "true" ]; then
  DIRECT=1; TARGET="$UPSTREAM"
  echo "You're a contributor to the catalog: the mod is published straight away."
else
  DIRECT=0
  echo "Making your own copy (fork) of $UPSTREAM, if you don't have one yet..."
  gh repo fork "$UPSTREAM" --clone=false >/dev/null 2>&1 || fail "couldn't fork $UPSTREAM."
  # shortcut: assumes the fork kept the name kif-discord-mods; a renamed fork needs KIF_PUBLISH_CACHE pointed at a clone of it
  TARGET="$LOGIN/kif-discord-mods"
fi

# 4. A copy of the catalog on this computer, on a new branch from the catalog's main
ORIGIN="$GITHUB/$TARGET.git"
if [ ! -d "$CACHE/.git" ]; then
  rm -rf "$CACHE"; mkdir -p "$CACHE"
  n=0
  until git -c core.autocrlf=false clone -q "$ORIGIN" "$CACHE"; do
    n=$((n + 1)); [ $n -ge 4 ] && fail "couldn't download $TARGET."
    echo "Waiting for GitHub to finish your copy..."; sleep 5
  done
fi
cd "$CACHE" || fail "can't open $CACHE."
git remote set-url origin "$ORIGIN"
git remote remove upstream >/dev/null 2>&1
git remote add upstream "$GITHUB/$UPSTREAM.git"
# pushes sign in through gh, in this copy only (your git settings stay as they are)
git config --local --unset-all credential.helper
git config --local --add credential.helper ""
git config --local --add credential.helper "!gh auth git-credential"
git config --local core.quotepath off
# the mod's files go up byte for byte, as the game checked them
git config --local core.autocrlf false
git fetch -q upstream main || fail "couldn't read $UPSTREAM."
git checkout -q -f -B "$BRANCH" upstream/main || fail "couldn't make the branch $BRANCH."
git clean -q -fdx

# 5. Contributors change only their own mod: a folder someone else last
# changed, or an id another folder uses, is for the catalog's owner
if [ "$DIRECT" = 1 ]; then
  if [ -n "$(git ls-tree -d --name-only upstream/main -- "$FOLDER")" ]; then
    OWNER="$(gh api "repos/$UPSTREAM/commits?path=${FOLDER// /%20}&sha=main&per_page=1" --jq '.[0].author.login' 2>/dev/null)"
    [ "$OWNER" = "null" ] && OWNER=""
    if [ -z "$OWNER" ]; then
      # an address GitHub doesn't link to an account: compare the address
      LAST="$(git log -1 --format=%ae upstream/main -- "$FOLDER")"
      { [ "$LAST" = "$EMAIL" ] || [ "$LAST" = "$LOGIN@users.noreply.github.com" ]; } && OWNER="$LOGIN"
    fi
    [ "$OWNER" = "$LOGIN" ] || fail "the catalog's $FOLDER folder was last changed by ${OWNER:-someone else}, not you. To change another modder's mod, ask Cody on the KIF Discord."
  fi
  # shortcut: a text search, so an "id" inside another mod's dependency list also stops it (the safe side); parse the JSON if that gets in the way
  OTHER="$(git grep -l -E "[^a-z0-9_]id.[[:space:]]*:[[:space:]]*.$ID[^a-z0-9_-]" upstream/main -- '*/mod.json' 2>/dev/null \
           | sed 's#^upstream/main:##; s#/mod\.json$##' | grep -vxF -- "$FOLDER" | head -n 1)"
  [ -z "$OTHER" ] || fail "the id $ID is already used by the catalog's $OTHER folder. Ask Cody on the KIF Discord."
fi

# 6. The mod's files (not its .git folder or KIF's install lists)
rm -rf "./$FOLDER"
mkdir -p "./$FOLDER"
cp -R "$MODDIR/." "./$FOLDER/" || fail "couldn't copy the mod's files."
find "./$FOLDER" -name .git -prune -exec rm -rf {} +
rm -f "./$FOLDER/.kif_installed" "./$FOLDER/.installed_assets"
git add -A -- "$FOLDER"
if git diff --cached --quiet; then
  echo; echo "Nothing to upload: the catalog already has exactly these files."; finish 0
fi
git -c user.name="$LOGIN" -c user.email="$EMAIL" commit -q --cleanup=verbatim -F "$MSGFILE" \
  || fail "couldn't save the change (git commit)."
OUTSIDE="$(git diff --name-only upstream/main HEAD | awk -v p="$FOLDER/" 'index($0, p) != 1' | head -n 1)"
[ -z "$OUTSIDE" ] || fail "the change would touch $OUTSIDE, outside the mod's folder."
echo "Files ready:"
git --no-pager show --stat --format= HEAD | tail -n 15

if [ "${KIF_PUBLISH_DRY:-}" = "1" ]; then
  echo
  if [ "$DIRECT" = 1 ]; then echo "Dry run: would publish $FOLDER straight to $UPSTREAM main."
  else echo "Dry run: would push $BRANCH to $TARGET and open a pull request to $UPSTREAM."; fi
  finish 0
fi

# 7a. Contributors: straight to main
if [ "$DIRECT" = 1 ]; then
  git push -q origin "HEAD:main" || fail "couldn't publish: the catalog changed while this ran. Run it again."
  echo
  echo "Published: players get it at their next catalog check."
  echo "The catalog's check runs on every change; a red X here means something needs fixing:"
  echo "  https://github.com/$UPSTREAM/commits/main"
  finish 0
fi

# 7b. Everyone else: the fork's branch, then the pull request (an open one
# for this branch is updated by the push)
if git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null \
   && git diff --quiet "origin/$BRANCH" HEAD -- "$FOLDER"; then
  echo; echo "Nothing to upload: your pull request already has exactly these files."; finish 0
fi
git push -q -f origin "$BRANCH" || fail "couldn't upload to $TARGET."
find_pr() { gh pr list --repo "$UPSTREAM" --head "$BRANCH" --state open --author "$LOGIN" --json url --jq '.[].url' | head -n 1; }
URL="$(find_pr)"
if [ -n "$URL" ]; then
  echo "Your open pull request is updated."
else
  TITLE="$(head -n 1 "$MSGFILE")"
  gh pr create --repo "$UPSTREAM" --base main --head "$LOGIN:$BRANCH" --title "$TITLE" --body-file "$BODYFILE" >/dev/null \
    || fail "couldn't open the pull request."
  URL="$(find_pr)"
fi
echo
echo "Pull request: $URL"
echo "The catalog's check runs there within a few minutes, then the mod is reviewed. Fix anything the check reports and publish again."
[ -n "$URL" ] && gh pr view "$URL" --repo "$UPSTREAM" --web >/dev/null 2>&1
finish 0
