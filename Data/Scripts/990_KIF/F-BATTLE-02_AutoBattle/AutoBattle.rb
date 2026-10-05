#===============================================================================
# F-BATTLE-02 – Auto-Battle (Reïzod & Trapstarr)
# Source: KIF 0.20.7
#   011_Battle/003_Battle/002_PokeBattle_Battle.rb:287-290  pbOwnedByPlayer?
#     returns false while Auto-Battle is on, so the AI picks the player's moves
#     and replacements ("Ally controls player pokemon")
#   011_Battle/003_Battle/003_Battle_StartAndEnd.rb:161-185  Shiny Stop
#   011_Battle/005_Battle scene/006_PokeBattle_Scene.rb:200, :242  battle
#     messages advance on their own
#   052_AddOns/Spped Up.rb:42-100  title "Auto-Battler (ON/OFF)" and the X/Y
#     battle shortcuts
#   016_UI/015_UI_Options.rb:2316-2333  options (Battles & Pokemons)
#
# "Auto-Battle" (Off/On): the AI fights your battles. Battle text moves on by
#   itself. Prompts outside the battle text (learning a move, nicknames, ...)
#   still wait for you, like KIF.
# "Auto-Battle Shiny Stop": Auto-Battle switches itself off when a shiny wild
#   Pokémon appears.
# The window title shows "Auto-Battler (ON/OFF) | Loop Self-Battle (ON/OFF)".
#
# 6.8.2 adaptations:
#   * No battle shortcut keys (Cody, 2026-10-05): KIF's X (Auto-Battle) is
#     6.8.2's speed-up key and L/R are the KIF speed keys, so Auto-Battle and
#     Battle Loop are toggled in KIF Settings. KIF's "Auto-Battle Shortcut"
#     option is therefore not ported.
#   * The AI used is DemICE's Powerful AI (F-BATTLE-03), or 6.8.2's with
#     "Powerful AI" Off.
#===============================================================================
KIF::Options.define(:autobattler, 0, :save)
KIF::Options.define(:autobattlershiny, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Auto-Battle"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.autobattler },
                 proc { |value| $PokemonSystem.autobattler = value },
                 [_INTL("You fight your own battles"),
                  _INTL("Allows Trapstarr to take control of your pokemon")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Auto-Battle Shiny Stop"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.autobattlershiny },
                 proc { |value| $PokemonSystem.autobattlershiny = value },
                 [_INTL("Do NOT stop Auto-Battle if a shiny enemy is detected."),
                  _INTL("Automatically stops Auto-Battle if a shiny enemy is detected.")])
}

module KIF
  module AutoBattle
    @confirming = false
    class << self
      attr_accessor :confirming
    end

    def self.on?
      return $PokemonSystem && $PokemonSystem.autobattler.to_i == 1
    end
  end
end

class PokeBattle_Battle
  alias kif_auto_pbOwnedByPlayer? pbOwnedByPlayer? unless method_defined?(:kif_auto_pbOwnedByPlayer?)
  alias kif_auto_pbStartBattleSendOut pbStartBattleSendOut unless method_defined?(:kif_auto_pbStartBattleSendOut)

  def pbOwnedByPlayer?(idxBattler)
    return false if KIF::AutoBattle.on? && !opposes?(idxBattler)
    return kif_auto_pbOwnedByPlayer?(idxBattler)
  end

  # KIF battleStartShinyCheck (wild battles)
  def pbStartBattleSendOut(sendOuts)
    if wildBattle? && KIF::AutoBattle.on? && $PokemonSystem.autobattlershiny.to_i == 1
      if pbParty(1).any? { |p| p && p.shiny? }
        $PokemonSystem.autobattler = 0
      end
    end
    return kif_auto_pbStartBattleSendOut(sendOuts)
  end
end

# Battle text confirms itself while Auto-Battle is on
class PokeBattle_Scene
  [:pbDisplayMessage, :pbDisplay, :pbDisplayPausedMessage].each do |m|
    next unless method_defined?(m)
    orig = "kif_auto_#{m}".to_sym
    alias_method orig, m unless method_defined?(orig)
    define_method(m) do |*args, &block|
      old = KIF::AutoBattle.confirming
      KIF::AutoBattle.confirming = KIF::AutoBattle.on?
      begin
        return send(orig, *args, &block)
      ensure
        KIF::AutoBattle.confirming = old
      end
    end
  end
end

module Input
  class << Input
    alias kif_auto_trigger? trigger? unless method_defined?(:kif_auto_trigger?)
  end

  def self.trigger?(button)
    return true if KIF::AutoBattle.confirming && button == Input::USE
    return kif_auto_trigger?(button)
  end
end
