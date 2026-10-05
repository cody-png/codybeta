#===============================================================================
# F-POKE-02 – Item effect changes
# Source: KIF 0.20.7
#   052_AddOns/New Items effects.rb:1596-1599 Unfuse Traded (unfusetraded)
#   052_AddOns/New Items effects.rb:1133-1170 Transgender Stone (any gender)
#   052_AddOns/New Items effects.rb:1344-1353, :1371-1386, :1393-1396
#                                             Devolution Spray (pbForceDevo)
#   052_AddOns/New Balls.rb:64-68             Perfect Ball: two different IVs
#   052_AddOns/BattleLounge.rb:98-100         Rare Candy in the "multi" prizes
#   016_UI/015_UI_Options.rb:2298-2303        "Unfuse Traded" (default Off)
#
# 6.8.2 adaptations:
#   * Unfuse Traded: 6.8.2 checks pokemon.foreign?($Trainer) in
#     pokemonCanBeUnfused (Unfusing.rb:179) and unfusePokemonLegacy
#     (New Items effects.rb:1789). With the option On, foreign? answers false
#     only inside those two checks.
#   * Transgender Stone: KIF's 4th gender ("pizza") belongs to the KIF gender
#     feature; the stone ignores it until that is ported.
#   * Devolution Spray respects Evolution Lock (KIF did too).
#===============================================================================
KIF::Options.define(:unfusetraded, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Unfuse Traded"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.unfusetraded },
                 proc { |value| $PokemonSystem.unfusetraded = value },
                 [_INTL("You cannot unfuse traded Pokemons."),
                  _INTL("You can unfuse traded Pokemons.")])
}

#-------------------------------------------------------------------------------
# Unfuse Traded
#-------------------------------------------------------------------------------
module KIF
  @unfuse_check = false
  class << self
    attr_accessor :unfuse_check
  end

  def self.during_unfuse_check
    old = @unfuse_check
    @unfuse_check = true
    begin
      return yield
    ensure
      @unfuse_check = old
    end
  end
end

class Pokemon
  alias kif_items_foreign? foreign? unless method_defined?(:kif_items_foreign?)

  def foreign?(trainer)
    return false if KIF.unfuse_check && $PokemonSystem && $PokemonSystem.unfusetraded == 1
    return kif_items_foreign?(trainer)
  end
end

alias kif_items_pokemonCanBeUnfused pokemonCanBeUnfused unless defined?(kif_items_pokemonCanBeUnfused)

def pokemonCanBeUnfused(pokemon, scene)
  return KIF.during_unfuse_check { kif_items_pokemonCanBeUnfused(pokemon, scene) }
end

alias kif_items_unfusePokemonLegacy unfusePokemonLegacy unless defined?(kif_items_unfusePokemonLegacy)

def unfusePokemonLegacy(*args)
  return KIF.during_unfuse_check { kif_items_unfusePokemonLegacy(*args) }
end

#-------------------------------------------------------------------------------
# Transgender Stone: choose female / genderless / male
#-------------------------------------------------------------------------------
ItemHandlers::UseOnPokemon.add(:TRANSGENDERSTONE, proc { |item, pokemon, scene|
  if pokemon.respond_to?(:pizza?) && pokemon.pizza?
    scene.pbDisplay(_INTL("It won't have any effect."))
    next false
  end
  commands = []
  cmdFemale = cmdGenderless = cmdMale = -1
  commands[cmdFemale = commands.length] = _INTL("Make female") if pokemon.gender != 1
  commands[cmdGenderless = commands.length] = _INTL("Make genderless") if pokemon.gender != 2
  commands[cmdMale = commands.length] = _INTL("Make male") if pokemon.gender != 0
  commands << _INTL("Cancel")
  choice = scene.pbShowCommands(_INTL("Transgender to which gender?"), commands)
  if cmdFemale >= 0 && choice == cmdFemale
    pokemon.instance_variable_set(:@gender, 1)
    scene.pbRefresh
    scene.pbDisplay(_INTL("The Pokémon became female!"))
    next true
  elsif cmdMale >= 0 && choice == cmdMale
    pokemon.instance_variable_set(:@gender, 0)
    scene.pbRefresh
    scene.pbDisplay(_INTL("The Pokémon became male!"))
    next true
  elsif cmdGenderless >= 0 && choice == cmdGenderless
    pokemon.instance_variable_set(:@gender, 2)
    scene.pbRefresh
    scene.pbDisplay(_INTL("The Pokémon became genderless!"))
    next true
  end
  next false
})

#-------------------------------------------------------------------------------
# Devolution Spray
#-------------------------------------------------------------------------------
def getDevolvedSpecies(pokemon)
  return GameData::Species.get(pokemon.species).get_previous_species
end

def pbForceDevo(pokemon)
  return false if pokemon.respond_to?(:kif_evo_locked?) && pokemon.kif_evo_locked?
  evolution = getDevolvedSpecies(pokemon)
  return false if evolution.nil? || evolution == pokemon.species
  evo = PokemonEvolutionScene.new
  evo.pbStartScreen(pokemon, evolution)
  evo.pbEvolution
  evo.pbEndScreen
  return true
end

ItemHandlers::UseOnPokemon.add(:DEVOLUTIONSPRAY, proc { |item, pokemon, scene|
  next false if pokemon.egg?
  if pbForceDevo(pokemon)
    next true
  else
    scene.pbDisplay(_INTL("It won't have any effect."))
    next false
  end
})

#-------------------------------------------------------------------------------
# Perfect Ball: two *different* IVs become 31 (PIF could roll the same one
# twice, New Balls.rb:66-69)
#-------------------------------------------------------------------------------
BallHandlers::OnCatch.add(:PERFECTBALL, proc { |ball, battle, pokemon|
  perfects = [:ATTACK, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED, :DEFENSE, :HP].sample(2)
  pokemon.iv[perfects[0]] = 31
  pokemon.iv[perfects[1]] = 31
})

#-------------------------------------------------------------------------------
# Battle Lounge: Rare Candy can also be a multi-item prize
#-------------------------------------------------------------------------------
if defined?(GENERIC_PRIZES_MULTI) && GENERIC_PRIZES_MULTI.is_a?(Array) &&
   !GENERIC_PRIZES_MULTI.frozen? && !GENERIC_PRIZES_MULTI.include?(:RARECANDY)
  GENERIC_PRIZES_MULTI.push(:RARECANDY)
end
