#===============================================================================
# F-UI-01 – Kuray QoL pause menu (PC & Heal anywhere) + KIF "DEBUG" entry
# Source: KIF 0.20.7 016_UI/001_UI_PauseMenu.rb:105-300 (#KurayX)
#
# "Kuray QoL" (kurayqol, per-save, default On) adds "PC" and "Heal Pokémon" to
# the pause menu. Both are refused on the Elite Four / Mt. Silver / dream /
# Victory Road maps ("Can't use that here." then the menu closes), unless the
# developer marker DemICE.krs exists (KIF only bypassed that for Heal; here
# it bypasses both – KIF's PC check ignored the marker, see port notes).
# "Kuray Shop" and "Tutor.net" entries are added by their own features.
#
# KIF option "DEBUG" (global): handled by KIF.sync_debug (real debug mode).
#===============================================================================
KIF::Options.define(:kurayqol, 1, :save)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Kuray QoL"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.kurayqol },
                 proc { |value| $PokemonSystem.kurayqol = value },
                 [_INTL("Don't use Kuray's QoL features (PC and Heal in the menu)"),
                  _INTL("Use Kuray's QoL features (PC and Heal in the menu)")])
}

KIF::PauseMenu.add(:kif_pc, "PC", icon: "menuIcons/POKEMON",
  condition: proc { $PokemonSystem.kurayqol == 1 },
  handler: proc { |scene|
    if KIF::PauseMenu.restricted?
      scene.pbHideMenu
      pbMessage(_INTL("Can't use that here."))
      next :close
    end
    pbPlayDecisionSE
    $game_temp.fromkurayshop = 1
    pbFadeOutIn {
      storage_scene = PokemonStorageScene.new
      screen = PokemonStorageScreen.new(storage_scene, $PokemonStorage)
      screen.pbStartScreen(0)
    }
    $game_temp.fromkurayshop = nil
    :stay
  })

KIF::PauseMenu.add(:kif_heal, "Heal Pokémon", icon: "menuIcons/POKEMON",
  condition: proc { $PokemonSystem.kurayqol == 1 },
  handler: proc { |scene|
    if KIF::PauseMenu.restricted?
      scene.pbHideMenu
      pbMessage(_INTL("Can't use that here."))
      next :close
    end
    $Trainer.heal_party
    pbMessage(_INTL("Pokemons healed!"))
    :stay
  })

# KIF option "DEBUG": now forces PIF's real debug mode (see
# 000_Core/002_KIF_Options.rb KIF.sync_debug), so PIF's own "Debug" entry
# appears and no separate KIF entry is needed.
