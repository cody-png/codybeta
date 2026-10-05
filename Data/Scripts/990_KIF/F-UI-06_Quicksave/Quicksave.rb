#===============================================================================
# F-UI-06 – Quicksave
# Source: KIF 0.20.7 052_AddOns/Quicksave.rb ("by Marin, updated by CrystalStar")
#
# "Quicksave with S" (quicksave, global, default On): pressing S on the map
# opens the normal save screen.
# Key: KIF checked Input::JUMPDOWN, which KIF had defined as Input::Y (the S key
# in RMXP/mkxp default bindings). PIF 6.8.2 redefines JUMPDOWN = Input::R (not
# S), so the port checks Input::Y directly. Input::Y is unused on the map in
# 6.8.2 (speed-up is Input::X).
#
# KIF's file also redefined Scene_Map#pbSaveScreen with Essentials v20 code
# (Game.save, $player) that is never called: its update hook calls
# `Scene_Map.pbSaveScreen`, which resolves to the global pbSaveScreen
# (016_UI/014_UI_Save.rb:124, 6.8.2 MultiSaves slot screen). Only the working
# part is ported.
# Added guards (not in KIF): not while an event runs, a message is showing,
# the player is moving, saving is disabled, or Hoenn furniture is being moved.
#===============================================================================
KIF::Options.define(:quicksave, 1, :global)

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Quicksave with S"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.quicksave },
                 proc { |value| $PokemonSystem.quicksave = value },
                 _INTL("Quicksave with S"))
}

class Scene_Map
  alias kif_quicksave_update update unless method_defined?(:kif_quicksave_update)

  def update
    kif_quicksave_update
    return unless $scene == self
    return unless $PokemonSystem && $PokemonSystem.quicksave == 1
    return unless Input.trigger?(Input::Y)
    return if $game_temp.message_window_showing || pbMapInterpreterRunning?
    return if $game_player.moving?
    return if $game_system && $game_system.save_disabled
    return if $game_temp.respond_to?(:moving_furniture) && $game_temp.moving_furniture
    pbSaveScreen
  end
end
