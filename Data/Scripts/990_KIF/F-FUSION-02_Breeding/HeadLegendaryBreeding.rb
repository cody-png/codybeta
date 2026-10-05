#===============================================================================
# F-FUSION-02 – Breeding restorations ("Head Legendary Breeding", Reïzod)
# Source: KIF 0.20.7
#   012_Overworld/007_Overworld_DayCare.rb:121-148 (pbDayCareGetCompat)
#   010_Data/001_Hardcoded data/003_EggGroup.rb:33-36 (:HeadUndiscovered)
#   048_Fusion/FusedSpecies.rb:58, :388-397 (calculate_egg_groups)
#   016_UI/015_UI_Options.rb:2341-2346 (option, default Off)
#
# With the option On, a fusion whose head is unbreedable (Undiscovered egg
# group, e.g. a legendary) can still breed through its body's egg groups, like
# old PIF. Two such fusions also match each other ("Head Undiscovered").
# A fusion whose BODY is Undiscovered never breeds.
#
# Already in 6.8.2, so not ported: breeding fused Pokémon at all (6.4.5 had
# disabled it; 6.8.2 FusedSpecies#calculate_egg_groups is back) and fusion
# genders (6.8.2 gives 50/50 unless a part is genderless; KIF's
# "gender ratio of the body" was a 6.4.5 workaround).
#
# 6.8.2 adaptation: KIF rewrote the head's egg groups inside
# calculate_egg_groups with map!, which changed the head species' own data
# for the rest of the session (a legendary then showed "Head Undiscovered"
# everywhere and Battle Frontier needed a patch). Here the substitute groups
# are only computed for the Day Care check; species data is not touched.
#===============================================================================
KIF::Options.define(:legendarybreed, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Head Legendary Breeding"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.legendarybreed },
                 proc { |value| $PokemonSystem.legendarybreed = value },
                 [_INTL("Legendary Head cannot breed (like new PIF)."),
                  _INTL("Legendary Head can breed (like old PIF).")])
}

GameData::EggGroup.register({
  :id   => :HeadUndiscovered,
  :name => _INTL("Head Undiscovered")
}) unless GameData::EggGroup.exists?(:HeadUndiscovered)

module KIF
  module Breeding
    # KIF calculate_egg_groups (FusedSpecies.rb:388-397), without changing
    # the species' arrays.
    def self.egg_groups(pkmn)
      sp = pkmn.species_data
      groups = Array(sp.egg_groups)
      return groups unless $PokemonSystem.legendarybreed == 1
      return groups unless sp.is_a?(GameData::FusedSpecies) && sp.head_pokemon && sp.body_pokemon
      body = Array(sp.body_pokemon.egg_groups)
      head = Array(sp.head_pokemon.egg_groups)
      return [:Undiscovered] if body.include?(:Undiscovered)
      head = head.map { |g| (g == :Undiscovered) ? :HeadUndiscovered : g }
      return (body + head).uniq
    end
  end
end

KIF.guard_base("012_Overworld/007_Overworld_DayCare.rb", 1861984085, "pbDayCareGetCompat")

# Copy of 6.8.2 pbDayCareGetCompat (007_Overworld_DayCare.rb:130-156) using
# KIF::Breeding.egg_groups.
def pbDayCareGetCompat
  return 0 if pbDayCareDeposited != 2
  pkmn1 = $PokemonGlobal.daycare[0][0]
  pkmn2 = $PokemonGlobal.daycare[1][0]
  # Shadow Pokémon cannot breed
  return 0 if pkmn1.shadowPokemon? || pkmn2.shadowPokemon?
  # Pokémon in the Undiscovered egg group cannot breed
  egg_groups1 = KIF::Breeding.egg_groups(pkmn1)   # KIF
  egg_groups2 = KIF::Breeding.egg_groups(pkmn2)   # KIF
  return 0 if egg_groups1.include?(:Undiscovered) ||
    egg_groups2.include?(:Undiscovered)
  # Pokémon that don't share an egg group (and neither is in the Ditto group)
  # cannot breed
  return 0 if !egg_groups1.include?(:Ditto) &&
    !egg_groups2.include?(:Ditto) &&
    (egg_groups1 & egg_groups2).length == 0
  # Pokémon with incompatible genders cannot breed
  return 0 if !pbDayCareCompatibleGender(pkmn1, pkmn2)
  # Pokémon can breed; calculate a compatibility factor
  ret = 1
  ret += 1 if pkmn1.species == pkmn2.species
  ret += 1 if pkmn1.owner.id != pkmn2.owner.id
  return ret
end

#-------------------------------------------------------------------------------
# Gender (found in Cody's play test 2026-10-05: Mew/Murkrow + Murkrow said
# "prefer to play with other Pokémon"). 6.8.2 makes a fusion genderless when
# either part is genderless, and genderless Pokémon only breed with Ditto.
# Legendary heads are almost all genderless, so with the option On such a
# fusion takes its gender from its body like old PIF/KIF
# (FusedSpecies#calculate_gender returned the body's ratio, KIF
# FusedSpecies.rb:427). Same personalID formula as Pokemon#gender, so the
# gender is stable. Only applies while the option is On; the stored gender is
# not changed.
#-------------------------------------------------------------------------------
class Pokemon
  def kif_head_legendary_gender
    return nil unless $PokemonSystem && $PokemonSystem.legendarybreed == 1
    sp = species_data
    return nil unless sp.is_a?(GameData::FusedSpecies) && sp.head_pokemon && sp.body_pokemon
    return nil unless Array(sp.head_pokemon.egg_groups).include?(:Undiscovered)
    return nil if Array(sp.body_pokemon.egg_groups).include?(:Undiscovered)
    return nil if @gender == 0 || @gender == 1   # already has a gender
    case sp.body_pokemon.gender_ratio
    when :AlwaysMale   then return 0
    when :AlwaysFemale then return 1
    when :Genderless   then return nil
    end
    female_chance = GameData::GenderRatio.get(sp.body_pokemon.gender_ratio).female_chance
    return ((@personalID & 0xFF) < female_chance) ? 1 : 0
  rescue
    return nil
  end

  alias kif_breed_gender gender unless method_defined?(:kif_breed_gender)

  def gender
    g = kif_head_legendary_gender
    return g unless g.nil?
    return kif_breed_gender
  end
end

#-------------------------------------------------------------------------------
# Crash fix (Cody's play test 2026-10-05: "undefined method include? for
# :Undiscovered:Symbol" at the Day Care). 6.8.2 FusedSpecies#calculate_egg_groups
# returns the bare Symbol :Undiscovered (not an Array) when a part is
# unbreedable, and pbIsDitto? (007_Overworld_DayCare.rb:116) calls include? on
# it. Vanilla never reaches pbIsDitto? for such a fusion (the Undiscovered
# check returns first); with Head Legendary Breeding it does. Same method,
# made array-safe.
#-------------------------------------------------------------------------------
def pbIsDitto?(pkmn)
  return Array(pkmn.species_data.egg_groups).include?(:Ditto)
end
