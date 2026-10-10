#===============================================================================
# KIF overlay for Pokémon Infinite Fusion 6.8.2
#
# This folder re-implements Kuray's Infinite Fusion (KIF 0.20.7) features on top
# of PIF 6.8.2 WITHOUT editing base PIF scripts wherever possible.
#
# Load order (see Data/Scripts.rxdata -> load_scripts_from_folder):
#   files in a folder load first (sorted by name), then sub-folders (sorted).
#   "990_KIF" sorts after every base folder except 998_Experimental/999_Main,
#   so every base class/method already exists when these files run.
#
# Conventions
#   * Each ported feature lives in its own sub-folder named after its
#     inventory ID (e.g. "F-BATTLE-09_ExpEvIvModes").
#   * Base behaviour is changed with `alias kif_<name> <name>` + redefinition
#     (guarded by `unless method_defined?` so files can be re-loaded by mods).
#   * Every KIF setting is declared through KIF::Options (000_Core), which
#     defines the $PokemonSystem accessor, its default, its scope
#     (:global or :save) and its menu entry. A feature that is not ported
#     yet therefore never shows a dead toggle.
#   * ONLY .rb files may live in this folder: the loader evals every file it
#     finds. Images/assets go to Graphics/Pictures/KIF/ (new files only).
#   * Save data only ever contains core Ruby types (Integer/String/Array/Hash/
#     Symbol), so a save made with this overlay still loads in vanilla PIF.
#
# Base files edited in place: none (Game.ini's Title is changed so old KIF
# saves are found).
#===============================================================================
module KIF
  PORT_VERSION = "0.21.10"
end
