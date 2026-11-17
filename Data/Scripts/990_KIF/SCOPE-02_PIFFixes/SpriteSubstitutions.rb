#===============================================================================
# SCOPE-02 - PIF fix: a missing sprite choice list doesn't crash (2026-11-15)
# PIF sets $PokemonSystem.alt_sprite_substitutions to {} only from its load
# screen (Continue, New Game) and reads it with no check in about ten places
# (BattleSpriteLoader#get_pif_sprite_from_species and others). A PokemonSystem
# that missed that step has nil there: Cephr's 1.2.13 save had no such field
# at all, and every starter ball in Oak's Lab crashed with "undefined method
# [] for nil". The reader now always gives a Hash.
#===============================================================================
class PokemonSystem
  def alt_sprite_substitutions
    @alt_sprite_substitutions = {} unless @alt_sprite_substitutions.is_a?(Hash)
    return @alt_sprite_substitutions
  end
end
