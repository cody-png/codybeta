#===============================================================================
# SCOPE-02 – PIF fix (2.0.8): a Pokedex sized for another species count
# A save made in a build with 1,201 species (a player's File B) keeps fusion
# Pokedex tables of 1,203 rows; PIF only resizes tables that are too short
# (005_Player_Pokedex.rb resyncPokedexIfNumberOfPokemonChanged), and
# seen_fusion?/owned_fusion? read @seen_fusion[head][body] with no check, so a
# missing row crashed the Pokedex menu ("undefined method [] for nil", line
# 167). Tables of any other size are rebuilt to KIF's 576 species (numbers
# 1-576 mean the same species in both), and a missing row reads as not seen.
#===============================================================================
module KIF
  module PokedexRows
    # the tables last found right (by object, so a loaded save is checked once;
    # nothing is added to the save). seen?/owned? call this for every species.
    @checked = nil
    class << self; attr_accessor :checked; end

    def resyncPokedexIfNumberOfPokemonChanged
      tables = [@seen_standard, @owned_standard, @seen_fusion, @owned_fusion]
      ids = tables.map(&:object_id)
      return if KIF::PokedexRows.checked == ids
      want = NB_POKEMON + 2   # initStandardDexArray / initFusionDexArray: a nil slot, then 0..NB
      ok = tables.all? { |t| t.is_a?(Array) && t.length == want } &&
           [@seen_fusion, @owned_fusion].all? { |t| t[1..].all? { |r| r.is_a?(Array) && r.length == want } }
      if ok
        KIF::PokedexRows.checked = ids
        return
      end
      [:@seen_standard, :@owned_standard, :@seen_fusion, :@owned_fusion].each do |iv|
        instance_variable_set(iv, []) unless instance_variable_get(iv).is_a?(Array)
      end
      resync_pokedex
      KIF.log("Pokedex tables were not sized for #{NB_POKEMON} species; rebuilt") rescue nil
      KIF::PokedexRows.checked = [@seen_standard, @owned_standard, @seen_fusion, @owned_fusion].map(&:object_id)
    end

    def seen_fusion?(species)
      bodyId = getBodyID(species)
      row = @seen_fusion[getHeadID(species, bodyId)]
      return row[bodyId] if row.is_a?(Array)
      KIF::PokedexRows.checked = nil   # the next seen?/owned? rebuilds the tables
      return false
    end

    def owned_fusion?(species)
      bodyId = getBodyID(species)
      row = @owned_fusion[getHeadID(species, bodyId)]
      return row[bodyId] == true if row.is_a?(Array)
      KIF::PokedexRows.checked = nil
      return false
    end
  end
end

class Player
  class Pokedex
    prepend KIF::PokedexRows
  end
end
