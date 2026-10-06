#===============================================================================
# KIF::Perf – overlay-side performance fixes for base PIF 6.8.2 behaviour
# (base files are never edited).
#
# Pokemon#species_data for a fusion: 6.8.2 (001_Pokemon.rb:252-255) calls
# GameData::Species.get(@species) on every read, and for fused ids
# (010_Data/001_GameData.rb:37-53) that builds a brand-new FusedSpecies each
# time: merged movesets, tutor/egg moves, evolutions, name, dex entry, ...
# Pokemon#type1/type2/baseStats/calc_stats/moves checks all go through it,
# so a fusion in the party rebuilt its species data hundreds of times per
# screen and the AI thousands of times per turn.
# Here the built object is kept on the Pokémon and reused while its species
# is unchanged and the game data hasn't been reloaded (boot/compile token).
# Non-fused species keep 6.8.2's lookup (DATA already returns one object).
# A Pokémon loaded from a save carries an old token, so it rebuilds once.
#===============================================================================
module KIF
  module Perf
    @token = rand(2**30) + 1

    def self.token; @token; end
    def self.bump_token; @token = rand(2**30) + 1; end
  end
end

module KIF
  module DataLoad
    class << self
      alias kif_perf_run run unless method_defined?(:kif_perf_run)

      def run
        KIF::Perf.bump_token
        kif_perf_run
      end
    end
  end
end

class Pokemon
  alias kif_perf_species_data species_data unless method_defined?(:kif_perf_species_data)

  def species_data
    sd = @species_data
    if sd && @kif_sd_token == KIF::Perf.token && sd.species == @species
      return sd
    end
    sd = kif_perf_species_data
    @kif_sd_token = KIF::Perf.token
    return sd
  end
end
