#===============================================================================
# SCOPE-02 – PIF fix: picking a wild Pokémon from a map's table works
# (2026-10-22)
# PokemonEncounters#choose_wild_pokemon_for_map (012/002/003) rolls with
# `chance_rolls`, which it never takes as a parameter: on any map with a
# table it raised NameError, so the Bug-Catching Contest crashed when it
# picked a Pokémon. Overworld Encounters fixes it for itself the same way.
# Same code as PIF's, with the parameter (1 roll by default, as in
# choose_wild_pokemon).
#===============================================================================
class PokemonEncounters
  alias kif_cfm_choose_wild_pokemon_for_map choose_wild_pokemon_for_map unless method_defined?(:kif_cfm_choose_wild_pokemon_for_map)

  def choose_wild_pokemon_for_map(map_ID, enc_type, chance_rolls = 1)
    if !enc_type || !GameData::EncounterType.exists?(enc_type)
      raise ArgumentError.new(_INTL("Encounter type {1} does not exist", enc_type))
    end
    encounter_data = getEncounterMode().get(map_ID, $PokemonGlobal.encounter_version)
    return nil if !encounter_data
    enc_list = encounter_data.types[enc_type]
    return nil if !enc_list || enc_list.length == 0
    chance_total = 0
    enc_list.each { |a| chance_total += a[0] }
    rnd = 0
    chance_rolls.times do
      r = rand(chance_total)
      rnd = r if r > rnd   # prefer rarer entries if rolling repeatedly
    end
    encounter = nil
    enc_list.each do |enc|
      rnd -= enc[0]
      next if rnd >= 0
      encounter = enc
      break
    end
    level = rand(encounter[2]..encounter[3])
    return [encounter[1], level]
  end
end
