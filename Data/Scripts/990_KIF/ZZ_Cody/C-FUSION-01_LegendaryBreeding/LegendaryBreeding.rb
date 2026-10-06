#===============================================================================
# C-FUSION-01 – Legendary Breeding (Cody)
# Cody Settings → Breeding & Fusion → "Legendary Breeding" (per save,
# default Off).
#
# With it On, a legendary (LEGENDARIES_LIST, or a fusion with a legendary
# head or body) can breed with any Pokémon that can breed: no egg-group or
# gender check for the pair. Baby Pokémon and Unown (also "Undiscovered")
# still can't breed, nor can Shadow Pokémon.
# The Egg (Cody): each parent gives one species (a fusion parent gives its
# head or body at random). If they differ, the Egg is 25% each: parent A,
# parent B, A-head/B-body fusion, B-head/A-body fusion – e.g. Mewtwo + Vulpix
# → Mewtwo, Vulpix, Mewpix or Vultwo. With Ditto, the Egg is the other
# parent's. The rest of the Egg (moves, forms, IVs) is 6.8.2's.
#===============================================================================
KIF::Options.define(:cody_legendarybreed, 0, :save)

KIF::Options.add(:cody_breeding, :save) {
  EnumOption.new(_INTL("Legendary Breeding"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.cody_legendarybreed },
                 proc { |value| $PokemonSystem.cody_legendarybreed = value },
                 [_INTL("Legendary Pokémon can't breed."),
                  _INTL("Legendary Pokémon can breed with any Pokémon.")])
}

module KIF
  module LegendaryBreeding
    def self.on?
      return $PokemonSystem && $PokemonSystem.cody_legendarybreed.to_i == 1
    end

    def self.legendary_species?(sp)
      return defined?(LEGENDARIES_LIST) && LEGENDARIES_LIST.include?(sp)
    end

    def self.legendary?(pkmn)
      return false if !pkmn || pkmn.egg?
      sp = pkmn.species_data
      if sp.is_a?(GameData::FusedSpecies) && sp.head_pokemon && sp.body_pokemon
        return legendary_species?(sp.head_pokemon.species) || legendary_species?(sp.body_pokemon.species)
      end
      return legendary_species?(pkmn.species)
    end

    def self.ditto?(pkmn)
      return pkmn.species == :DITTO || (pbIsDitto?(pkmn) rescue false)
    end

    # Can this Pokémon breed at all (ignoring its partner)?
    def self.can_breed?(pkmn)
      return false if pkmn.shadowPokemon?
      return true if legendary?(pkmn)
      groups = Array(pkmn.species_data.egg_groups)
      return !groups.include?(:Undiscovered)
    end

    # One species from a parent: a fusion gives its head or body
    def self.parent_species(pkmn)
      sp = pkmn.species_data
      if sp.is_a?(GameData::FusedSpecies) && sp.head_pokemon && sp.body_pokemon
        return [sp.head_pokemon.species, sp.body_pokemon.species].sample
      end
      return pkmn.species
    end
  end
end

alias cody_legend_pbDayCareGetCompat pbDayCareGetCompat unless defined?(cody_legend_pbDayCareGetCompat)

def pbDayCareGetCompat
  return cody_legend_pbDayCareGetCompat unless KIF::LegendaryBreeding.on? && pbDayCareDeposited == 2
  pkmn1 = $PokemonGlobal.daycare[0][0]
  pkmn2 = $PokemonGlobal.daycare[1][0]
  lb = KIF::LegendaryBreeding
  return cody_legend_pbDayCareGetCompat unless lb.legendary?(pkmn1) || lb.legendary?(pkmn2)
  return 0 unless lb.can_breed?(pkmn1) && lb.can_breed?(pkmn2)
  ret = 1
  ret += 1 if pkmn1.species == pkmn2.species
  ret += 1 if pkmn1.owner.id != pkmn2.owner.id
  return ret
end

alias cody_legend_determineDayCareEggSpecies determineDayCareEggSpecies unless defined?(cody_legend_determineDayCareEggSpecies)

def determineDayCareEggSpecies(maleParent, femaleParent)
  lb = KIF::LegendaryBreeding
  unless lb.on? && (lb.legendary?(maleParent) || lb.legendary?(femaleParent))
    return cody_legend_determineDayCareEggSpecies(maleParent, femaleParent)
  end
  return lb.parent_species(femaleParent) if lb.ditto?(maleParent)
  return lb.parent_species(maleParent) if lb.ditto?(femaleParent)
  a = lb.parent_species(maleParent)
  b = lb.parent_species(femaleParent)
  return a if a == b
  case rand(4)
  when 0 then return a
  when 1 then return b
  when 2 then return fusionOf(a, b)
  else        return fusionOf(b, a)
  end
end
