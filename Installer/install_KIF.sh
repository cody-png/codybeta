#!/usr/bin/env bash
# ============================================================================
#  KIF installer for Linux / Steam Deck
#  Put this file in the folder you want and run it: double-click it (after
#  Properties > Permissions > "Is executable"), right-click > Run in Konsole,
#  or bash install_KIF.sh. It makes a "KIF" folder next to itself,
#  downloads the game from GitHub into it and unpacks it.
#  KIF is a Windows game: it runs through Wine or Proton (see the end).
#  After that the game keeps itself up to date (in-game updater).
#  Needs about 4.5 GB free while installing (about 1 to 2 GB once done).
#  Options: --stable / --beta (skip the question), KIF_INSTALL_URL=<url> to
#  download from somewhere else (testing).
# ============================================================================
set -u

# Started by double-click (no terminal): open one, so the questions and the
# download progress can be seen, and keep it open at the end.
if [ ! -t 0 ] && [ -z "${KIF_IN_TERMINAL:-}" ]; then
  export KIF_IN_TERMINAL=1
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  for t in konsole gnome-terminal kgx xfce4-terminal mate-terminal lxterminal x-terminal-emulator xterm; do
    command -v "$t" >/dev/null 2>&1 || continue
    case "$t" in
      gnome-terminal|kgx) exec "$t" -- bash "$self" "$@" ;;
      *)                  exec "$t" -e bash "$self" "$@" ;;
    esac
  done
fi
if [ -n "${KIF_IN_TERMINAL:-}" ] && [ -t 0 ]; then
  trap 'printf "\n  Press Enter to close this window. "; read -r _' EXIT
fi
REPO="https://github.com/cody-png/codybeta/archive/refs/heads"
TAGS="https://github.com/cody-png/codybeta/archive/refs/tags"
# PIN: the version a release's installer belongs to (set when a release is
# published, e.g. 1.1.0); empty = only Stable / Beta are offered.
PIN=""
HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HERE/KIF"
ZIP="$TARGET/KIF_download.zip"
UNPACK="$TARGET/.kif_unpack"

say()  { printf '%s\n' "$*"; }
fail() { say ""; say "  $*"; rm -rf "$ZIP" "$UNPACK"; rmdir "$TARGET" 2>/dev/null; exit 1; }
ask()  { # ask "question" default -> answer (default when not interactive)
  local a=""
  if [ -t 0 ]; then read -r -p "  $1 " a; fi
  [ -z "$a" ] && a="$2"
  printf '%s' "$a"
}

say ""
say "  ==================================="
say "    KIF installer"
say "  ==================================="
say ""
say "  The game will be installed into:"
say "    $TARGET"
say ""

if command -v curl >/dev/null 2>&1; then DL=curl
elif command -v wget >/dev/null 2>&1; then DL=wget
else fail "This installer needs curl or wget."; fi

if [ -f "$TARGET/InfiniteFusion.exe" ]; then
  say "  KIF is already installed there. Reinstalling downloads the game again"
  say "  and puts back missing or damaged game files; saves, mods and imported"
  say "  sprites are kept. (To just update, start the game: it updates itself.)"
  case "$(ask '[R] Reinstall  [C] Cancel :' C)" in
    r|R) ;;
    *) say "  Nothing was changed."; exit 0 ;;
  esac
fi

BRANCH=""
for arg in "$@"; do
  case "$arg" in
    --beta) BRANCH="beta-testing" ;;
    --stable) BRANCH="release" ;;
    --pinned) [ -n "$PIN" ] && BRANCH="$PIN" ;;
  esac
done
if [ -z "$BRANCH" ]; then
  say "  Which version?"
  say "    [S] Stable - the newest released version, keeps itself updated (recommended)"
  say "    [B] Beta   - test builds: newest features, may have bugs"
  [ -n "$PIN" ] && say "    [V] KIF $PIN only - stays on this version, no updates"
  case "$(ask 'Choose S, B or V :' S)" in
    b|B) BRANCH="beta-testing" ;;
    v|V) if [ -n "$PIN" ]; then BRANCH="$PIN"; else BRANCH="release"; fi ;;
    *) BRANCH="release" ;;
  esac
fi
if [ -n "$PIN" ] && [ "$BRANCH" = "$PIN" ]; then
  URL="${KIF_INSTALL_URL:-$TAGS/$PIN.zip}"
else
  URL="${KIF_INSTALL_URL:-$REPO/$BRANCH.zip}"
fi

mkdir -p "$TARGET" 2>/dev/null || fail "Couldn't make the folder $TARGET - move the installer somewhere you can write to."
FREE_KB=$(df -Pk "$TARGET" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${FREE_KB:-}" ] && [ "$FREE_KB" -lt 4500000 ]; then
  fail "Not enough free space: about 4.5 GB is needed, $((FREE_KB / 1024)) MB is free."
fi

say ""
say "  Downloading KIF ($BRANCH) - about 1 to 2 GB, this takes a while..."
rm -f "$ZIP"
if [ "$DL" = curl ]; then
  curl -L --fail --retry 5 --retry-delay 3 -o "$ZIP" "$URL" || {
    [ "$BRANCH" = release ] && fail "The download failed. If this keeps happening there may be no Stable release yet - run again and choose B (Beta)."
    fail "The download failed. Check your internet connection and run the installer again."
  }
else
  wget -q --show-progress -O "$ZIP" "$URL" || fail "The download failed. Check your internet connection and run the installer again."
fi

say ""
say "  Unpacking (about 30,000 files)..."
rm -rf "$UNPACK"; mkdir -p "$UNPACK"
if command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$ZIP" -d "$UNPACK" || fail "Unpacking failed (not enough disk space, or the download was cut short)."
elif command -v bsdtar >/dev/null 2>&1; then
  bsdtar -xf "$ZIP" -C "$UNPACK" || fail "Unpacking failed (not enough disk space, or the download was cut short)."
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$ZIP" "$UNPACK" || fail "Unpacking failed (not enough disk space, or the download was cut short)."
else
  fail "This installer needs unzip, bsdtar or python3 to unpack the game."
fi
TOP="$(find "$UNPACK" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$TOP" ] && [ -f "$TOP/InfiniteFusion.exe" ] || fail "The download doesn't look like KIF (no InfiniteFusion.exe inside)."
cp -a "$TOP/." "$TARGET/" || fail "Copying the game into $TARGET failed (disk space?)."
rm -rf "$UNPACK" "$ZIP"
# a fixed version: the game skips its automatic update check (KIF_pinned.txt)
if [ -n "$PIN" ] && [ "$BRANCH" = "$PIN" ]; then printf '%s\n' "$PIN" > "$TARGET/KIF_pinned.txt"; else rm -f "$TARGET/KIF_pinned.txt"; fi

# a launcher: Wine if it is installed, otherwise Proton through Steam
cat > "$TARGET/run_KIF.sh" <<'LAUNCH'
#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
if command -v wine >/dev/null 2>&1; then
  exec wine InfiniteFusion.exe "$@"
fi
echo "Wine isn't installed. To play through Steam (Steam Deck):"
echo "  Steam > Games > Add a Non-Steam Game to My Library > Browse > pick"
echo "  $(pwd)/InfiniteFusion.exe"
echo "  then the game's Properties > Compatibility > Force a Steam Play"
echo "  compatibility tool (Proton)."
LAUNCH
chmod +x "$TARGET/run_KIF.sh"

say ""
say "  ==================================="
say "    KIF is installed!"
say "  ==================================="
say ""
say "  Folder: $TARGET"
say "  To play:"
say "    - with Wine:  run $TARGET/run_KIF.sh"
say "    - Steam Deck / Proton: Steam > Add a Non-Steam Game > Browse >"
say "      $TARGET/InfiniteFusion.exe, then Properties > Compatibility >"
say "      Force a Steam Play compatibility tool (Proton). Start it from Steam."
say "  Sprite pack: put the PIF sprite pack .zip into the \"Import Sprites\""
say "  folder inside KIF; the game installs it the next time it starts."
say ""
