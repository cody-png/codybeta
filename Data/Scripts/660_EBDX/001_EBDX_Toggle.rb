#===============================================================================
#  EBDX Toggle System for KIF Multiplayer
#===============================================================================
#  Adds a per-player toggle to switch between EBDX enhanced battles and
#  vanilla KIF battles. This is purely local - multiplayer sync is unaffected.
#===============================================================================

class PokemonSystem
  attr_accessor :mp_ebdx_enabled  # 0 = off (vanilla), 1 = on (EBDX visuals)

  alias ebdx_toggle_original_initialize initialize unless method_defined?(:ebdx_toggle_original_initialize)
  def initialize
    ebdx_toggle_original_initialize
    @mp_ebdx_enabled = 1  # On by default for EBDX visuals
  end
end

#===============================================================================
#  Global toggle check module
#===============================================================================
module EBDXToggle
  def self.enabled?
    return $PokemonSystem && $PokemonSystem.mp_ebdx_enabled == 1
  end
end
