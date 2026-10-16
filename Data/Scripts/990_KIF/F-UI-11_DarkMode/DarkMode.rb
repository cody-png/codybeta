#===============================================================================
# Dark Mode switch (port addition)
#
# PIF 6.8.2 has a dark mode for the Pokédex, Summary and PokéNav screens
# (isDarkMode, 052_InfiniteFusion/Gameplay/0_Utilities/MenuUtils.rb:420), but
# its only switch is the PokéNav "Toggle Dark/Light" app, and the PokéNav is
# Hoenn-mode content (Kanto saves only get it through Debug). This option in
# KIF Settings > Graphics (in-game, per save) flips the same 6.8.2 setting
# ($Trainer.pokenav.darkMode), so both switches stay in sync.
# It also switches on KIF 0.20.7's dark battle message box and command menu
# (F-BATTLE-07_BattleUI/BattleUI.rb).
#
# Fix: some 6.8.2 screens load a "_dark" image that this (Kanto) install
# doesn't ship – the battle command and fight buttons (cursor_command_dark,
# cursor_fight_dark) and blank party panels (panel_blank_dark) – so they
# vanished with dark mode on. A missing "_dark" image now falls back to the
# normal one (6.8.2's own setBitmap already does this; these places don't).
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
                  _INTL("Dark Pokédex, Summary, PokéNav and battle menus")])
}

# (the missing "_dark" image fallback is in SCOPE-02_PIFFixes/DarkImages.rb: PIF's
# own dark mode needs it, so it is never switched off)
