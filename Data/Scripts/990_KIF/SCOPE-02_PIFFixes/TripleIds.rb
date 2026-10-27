#===============================================================================
# SCOPE-02 – Triple fusions by number (2026-10-26)
#   PIF reads every species number above NB_POKEMON as a two-part fusion, so
#   GameData::Species.get(1000006) (Venustoizard) crashed (try_get too), as did
#   Pokemon.new, pbAddPokemonID and PBSpecies.getName with that number. Oak's
#   lab (map 659) gives the custom starter by number, so a triple fusion
#   starter could not work. Triple fusions have their own numbers from
#   Settings::ZAPMOLCUNO_NB (999999) up; two-part fusion numbers stay at or
#   below NB_POKEMON * NB_POKEMON + NB_POKEMON, so nothing else changes.
#   A triple's sprite by species (the lab's ball shows it) is PIF's triple
#   sprite instead of a made-up two-part fusion.
#   Always on (a crash fix, and Species.get is too hot for a module switch).
#===============================================================================
module GameData
  class Species
    class << self
      alias kif_ts_get get unless method_defined?(:kif_ts_get) || private_method_defined?(:kif_ts_get)

      def get(other)
        return self::DATA[other] if other.is_a?(Integer) && other >= Settings::ZAPMOLCUNO_NB && self::DATA.has_key?(other)
        return kif_ts_get(other)
      end

      alias kif_ts_try_get try_get unless method_defined?(:kif_ts_try_get) || private_method_defined?(:kif_ts_try_get)

      def try_get(other)
        return self::DATA[other] if other.is_a?(Integer) && other >= Settings::ZAPMOLCUNO_NB && self::DATA.has_key?(other)
        return kif_ts_try_get(other)
      end
    end
  end
end

class BattleSpriteLoader
  alias kif_ts_get_pif_sprite_from_species get_pif_sprite_from_species unless method_defined?(:kif_ts_get_pif_sprite_from_species) || private_method_defined?(:kif_ts_get_pif_sprite_from_species)

  def get_pif_sprite_from_species(species)
    data = GameData::Species.get(species)
    return select_new_pif_triple_sprite(data.id_number) if data.is_triple_fusion
    return kif_ts_get_pif_sprite_from_species(species)
  end
end
