#===============================================================================
# Dark Mode switch (port addition, Cody 2026-10-05)
#
# PIF 6.8.2 has a dark mode for the Pokédex, Summary and PokéNav screens
# (isDarkMode, 052_InfiniteFusion/Gameplay/0_Utilities/MenuUtils.rb:420), but
# its only switch is the PokéNav "Toggle Dark/Light" app, and the PokéNav is
# Hoenn-mode content (Kanto saves only get it through Debug). This option in
# KIF Settings > Graphics (in-game, per save) flips the same 6.8.2 setting
# ($Trainer.pokenav.darkMode), so both switches stay in sync.
# KIF 0.20.7's own battle-only dark mode (F-BATTLE-07) is a separate feature.
#===============================================================================
module KIF
  module DarkMode
    def self.on?
      return !!($Trainer && $Trainer.pokenav && $Trainer.pokenav.darkMode)
    end

    def self.set(value)
      return unless $Trainer
      $Trainer.pokenav = Pokenav.new unless $Trainer.pokenav
      $Trainer.pokenav.darkMode = value
    end
  end
end

KIF::Options.add(:graphics, :save) {
  EnumOption.new(_INTL("Dark Mode"), [_INTL("Off"), _INTL("On")],
                 proc { KIF::DarkMode.on? ? 1 : 0 },
                 proc { |value| KIF::DarkMode.set(value == 1) },
                 [_INTL("Light Pokédex, Summary and PokéNav screens"),
                  _INTL("Dark Pokédex, Summary and PokéNav screens (PIF's dark mode)")])
}
