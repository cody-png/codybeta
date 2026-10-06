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

#===============================================================================
# Pizza in the gender selectors (port addition, Cody 2026-10-05 play test 6:
# "Any Gender Selector should be able to select Pizza gender only while
# Kuray's Shenanigans is enabled.")
#   * Transgender Stone and Debug > Set gender get "Make pizza" while
#     Shenanigans is On; a pizza Pokémon can then be made male / female /
#     genderless again.
#   * Shenanigans Off: KIF behaviour (the stone has no effect on a pizza
#     Pokémon, no pizza option).
# Pizza is KIF's hidden roll (kuraygender < 256, F-POKE-03); making a
# Pokémon pizza sets a roll below 256, undoing it sets one of 256 or more.
#===============================================================================
module KIF
  module Shenanigans
    def self.pizza?(pkmn)
      return pkmn.respond_to?(:pizza?) && pkmn.pizza?
    end

    def self.make_pizza(pkmn)
      pkmn.kuraygender = rand(256)
    end

    def self.unpizza(pkmn)
      pkmn.kuraygender = 256 + rand(65536 - 256) if pizza?(pkmn)
    end
  end
end

KIF::Shenanigans::OLD_TRANSGENDER = ItemHandlers::UseOnPokemon[:TRANSGENDERSTONE] unless defined?(KIF::Shenanigans::OLD_TRANSGENDER)

ItemHandlers::UseOnPokemon.add(:TRANSGENDERSTONE, proc { |item, pokemon, scene|
  next KIF::Shenanigans::OLD_TRANSGENDER.call(item, pokemon, scene) unless KIF::Shenanigans.on?
  pizza = KIF::Shenanigans.pizza?(pokemon)
  choices = []
  choices << [:female, _INTL("Make female")] if pizza || pokemon.gender != 1
  choices << [:genderless, _INTL("Make genderless")] if pizza || pokemon.gender != 2
  choices << [:male, _INTL("Make male")] if pizza || pokemon.gender != 0
  choices << [:pizza, _INTL("Make pizza")] if !pizza
  cmd = scene.pbShowCommands(_INTL("Transgender to which gender?"), choices.map { |c| c[1] } + [_INTL("Cancel")])
  next false if cmd.nil? || cmd < 0 || cmd >= choices.length
  case choices[cmd][0]
  when :pizza
    KIF::Shenanigans.make_pizza(pokemon)
    msg = _INTL("The Pokémon became pizza!")
  when :female
    KIF::Shenanigans.unpizza(pokemon)
    pokemon.instance_variable_set(:@gender, 1)
    msg = _INTL("The Pokémon became female!")
  when :male
    KIF::Shenanigans.unpizza(pokemon)
    pokemon.instance_variable_set(:@gender, 0)
    msg = _INTL("The Pokémon became male!")
  when :genderless
    KIF::Shenanigans.unpizza(pokemon)
    pokemon.instance_variable_set(:@gender, 2)
    msg = _INTL("The Pokémon became genderless!")
  end
  scene.pbRefresh
  scene.pbDisplay(msg)
  next true
})

# Debug > Set gender (6.8.2 020_Debug/003_Debug menus/005_Debug_PokemonCommands.rb:773)
if defined?(PokemonDebugMenuCommands)
  KIF::Shenanigans::OLD_SETGENDER = PokemonDebugMenuCommands.getFunction("setgender", "effect") unless defined?(KIF::Shenanigans::OLD_SETGENDER)

  PokemonDebugMenuCommands.register("setgender", {
    "parent"      => "main",
    "name"        => _INTL("Set gender"),
    "always_show" => true,
    "effect"      => proc { |pkmn, pkmnid, heldpoke, settingUpBattle, screen|
      if !KIF::Shenanigans.on? && KIF::Shenanigans::OLD_SETGENDER
        next KIF::Shenanigans::OLD_SETGENDER.call(pkmn, pkmnid, heldpoke, settingUpBattle, screen)
      end
      cmd = 0
      loop do
        msg = if KIF::Shenanigans.pizza?(pkmn)
                _INTL("Gender is pizza.")
              else
                [_INTL("Gender is male."), _INTL("Gender is female.")][pkmn.male? ? 0 : 1]
              end
        cmd = screen.pbShowCommands(msg, [_INTL("Make male"), _INTL("Make female"),
                                          _INTL("Make pizza"), _INTL("Reset")], cmd)
        break if cmd < 0
        case cmd
        when 0
          KIF::Shenanigans.unpizza(pkmn)
          pkmn.makeMale
          screen.pbDisplay(_INTL("{1}'s gender couldn't be changed.", pkmn.name)) if !pkmn.male?
        when 1
          KIF::Shenanigans.unpizza(pkmn)
          pkmn.makeFemale
          screen.pbDisplay(_INTL("{1}'s gender couldn't be changed.", pkmn.name)) if !pkmn.female?
        when 2
          KIF::Shenanigans.make_pizza(pkmn)
        when 3
          pkmn.gender = nil
        end
        $Trainer.pokedex.register(pkmn) if !settingUpBattle
        screen.pbRefreshSingle(pkmnid)
      end
      next false
    }
  })
end
