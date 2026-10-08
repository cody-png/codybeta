#===============================================================================
# C-SYS-02 – Skip intro (Cody, 2026-10-08)
#   Cody Settings > Interface > "Skip intro": Off (default) / On.
#   On: the game starts at the title screen without the opening movie
#   (Gengar and Nidorino). The title screen and its music stay.
#   (A NoIntro.krs file in the save folder still goes straight to the load
#   screen, as in KIF.)
#===============================================================================
KIF::Options.define(:cody_skipintro, 0, :global)

KIF::Options.add(:cody_interface, :global) {
  EnumOption.new(_INTL("Skip intro"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.cody_skipintro },
                 proc { |value| $PokemonSystem.cody_skipintro = value },
                 [_INTL("The opening movie plays when the game starts."),
                  _INTL("The game starts at the title screen, without the opening movie.")])
}

module KIF
  module SkipIntro
    def self.on?
      return ($PokemonSystem.cody_skipintro rescue 0).to_i == 1
    end
  end
end

class Scene_Intro
  if method_defined?(:playIntroCinematic)
    alias kif_skip_playIntroCinematic playIntroCinematic unless method_defined?(:kif_skip_playIntroCinematic)

    def playIntroCinematic
      return if KIF::SkipIntro.on?
      kif_skip_playIntroCinematic
    end
  end
end
