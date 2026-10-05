#===============================================================================
# F-UI-10 – Kuray's Shenanigans (Reïzod)
# Source: KIF 0.20.7
#   016_UI/015_UI_Options.rb:2791-2796 "Kuray's Shenanigans" On/Off (Others,
#     per save, default On)
#   011_Battle/001_Battler/001_PokeBattle_Battler.rb:184-200 and
#   011_Battle/006_Other battle types/002_PokeBattle_SafariZone.rb:49-60
#     displayGenderPizza: the pizza icon in the battle box only with it On
#   011_Battle/001_Battler/004_Battler_Statuses.rb:554 "Everyone loves pizza!":
#     a pizza Pokémon's Attract works on anyone (no gender check)
#
# The whole feature in KIF 0.20.7 is these two easter eggs around the hidden
# "pizza" gender (F-POKE-03). The Summary, party and PC show the pizza icon
# either way (as KIF). KIF's intro-screen "shenanigans" were commented out.
#
# 6.8.2 adaptation: no copy of pbCanAttract?; while it runs for a pizza user
# with Shenanigans On, the user and target report opposite genders so the
# gender check passes (abilities like Oblivious still block it).
#===============================================================================
KIF::Options.define(:shenanigans, 0, :save)   # 0 On, 1 Off (KIF order)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Kuray's Shenanigans"), [_INTL("On"), _INTL("Off")],
                 proc { $PokemonSystem.shenanigans },
                 proc { |value| $PokemonSystem.shenanigans = value },
                 [_INTL("You're playing with Shenanigans! (Easter Eggs)"),
                  _INTL("You're playing normally! (No Easter Eggs)")])
}

module KIF
  module Shenanigans
    @attract = nil
    class << self
      attr_accessor :attract
    end

    def self.on?
      return $PokemonSystem && $PokemonSystem.shenanigans.to_i == 0
    end
  end
end

class PokeBattle_Battler
  alias kif_shen_displayGenderPizza displayGenderPizza unless method_defined?(:kif_shen_displayGenderPizza)
  alias kif_shen_pbCanAttract? pbCanAttract? unless method_defined?(:kif_shen_pbCanAttract?)
  alias kif_shen_gender gender unless method_defined?(:kif_shen_gender)

  def displayGenderPizza
    return false unless KIF::Shenanigans.on?
    return kif_shen_displayGenderPizza
  end

  def pbCanAttract?(user, showMessages = true)
    pkmn = user ? (user.effects[PBEffects::Illusion] || user.pokemon) : nil
    if KIF::Shenanigans.on? && pkmn && pkmn.respond_to?(:pizza?) && pkmn.pizza?
      old = KIF::Shenanigans.attract
      KIF::Shenanigans.attract = [user, self]
      begin
        return kif_shen_pbCanAttract?(user, showMessages)
      ensure
        KIF::Shenanigans.attract = old
      end
    end
    return kif_shen_pbCanAttract?(user, showMessages)
  end

  def gender
    pair = KIF::Shenanigans.attract
    if pair
      return 0 if equal?(pair[0])
      return 1 if equal?(pair[1])
    end
    return kif_shen_gender
  end
end

# Safari Zone battler (KIF had the same check there)
class PokeBattle_FakeBattler
  def displayGenderPizza
    return false unless KIF::Shenanigans.on?
    return @pokemon.respond_to?(:pizza?) && @pokemon.pizza?
  end
end
