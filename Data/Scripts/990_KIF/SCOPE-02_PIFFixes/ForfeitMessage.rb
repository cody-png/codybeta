#===============================================================================
# SCOPE-02 – no "You have no more Pokémon that can fight!" after a forfeit
# (2026-10-26)
# PIF 6.8.2 ends a forfeited trainer battle as a loss (008_Battle_Action_
# Running.rb:53-57, @decision = 2), and the loss branch of pbEndOfBattle
# (003_Battle_StartAndEnd.rb:481) always says the player has no Pokémon left,
# even with the whole team standing (26 Oct test: Charmander at 21/24 HP).
# That line is left out while the player's side still has a Pokémon that can
# fight; "You lost against ..." and the rest stay.
#===============================================================================
class PokeBattle_Battle
  alias kif_ff_pbDisplayPaused pbDisplayPaused unless method_defined?(:kif_ff_pbDisplayPaused)

  def pbDisplayPaused(msg, &block)
    return if @decision == 2 && msg == _INTL("You have no more Pokémon that can fight!") && !(pbAllFainted?(0) rescue true)
    return kif_ff_pbDisplayPaused(msg, &block)
  end
end
