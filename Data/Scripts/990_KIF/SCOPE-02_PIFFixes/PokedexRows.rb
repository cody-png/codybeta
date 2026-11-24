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
      legacy = !@seen_standard.is_a?(Array) && !@seen_fusion.is_a?(Array)
      [:@seen_standard, :@owned_standard, :@seen_fusion, :@owned_fusion].each do |iv|
        instance_variable_set(iv, []) unless instance_variable_get(iv).is_a?(Array)
      end
      resync_pokedex
      @seen_triple = {} unless @seen_triple.is_a?(Hash)
      @owned_triple = {} unless @owned_triple.is_a?(Hash)
      # Pokedexes from before the tables kept seen/owned as species hashes
      [[@seen, :set_seen], [@owned, :set_owned]].each do |h, m|
        next unless legacy && h.is_a?(Hash)
        h.each_key { |sp| (send(m, sp, false) rescue nil) if GameData::Species.exists?(sp) rescue nil }
      end
      KIF.log("Pokedex tables were not sized for #{NB_POKEMON} species; rebuilt") rescue nil
      KIF::PokedexRows.checked = [@seen_standard, @owned_standard, @seen_fusion, @owned_fusion].map(&:object_id)
    end

    def seen_fusion?(species)
      return fusion_entry(:@seen_fusion, species) == true
    end

    def owned_fusion?(species)
      return fusion_entry(:@owned_fusion, species) == true
    end

    private

    # A missing row or table reads as not seen. A table found missing after the
    # size check passed is rebuilt here once (2.0.9: a player's Pokedex still
    # crashed at seen_fusion? with the table itself gone) and logged with what
    # the Pokedex held, so the next log says where it came from.
    def fusion_entry(iv, species)
      body = getBodyID(species)
      head = getHeadID(species, body)
      t = instance_variable_get(iv)
      unless t.is_a?(Array)
        KIF.log("Pokedex: #{iv} was #{t.class} after the size check; rebuilding (#{instance_variables.map { |v| "#{v}=#{instance_variable_get(v).class}" }.join(' ')})") rescue nil
        KIF::PokedexRows.checked = nil
        resyncPokedexIfNumberOfPokemonChanged
        t = instance_variable_get(iv)
        return false unless t.is_a?(Array)
      end
      row = t[head]
      return row[body] if row.is_a?(Array)
      KIF::PokedexRows.checked = nil   # the next seen?/owned? rebuilds the tables
      return false
    end
  end
end

class Player
  class Pokedex
    prepend KIF::PokedexRows
  end
end
