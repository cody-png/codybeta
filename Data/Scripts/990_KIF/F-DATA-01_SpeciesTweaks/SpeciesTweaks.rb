#===============================================================================
# F-DATA-01 – KIF species data tweaks
# Source: KIF 0.20.7 201_Kuray/003_KurayPokemonRevamp.rb
#   (GameData.kuray_rewritepokemons, re-registered every species at load).
#
# That file is a copy of PIF 6.4.5's species data. Compared with 6.4.5 it
# changes only six things; loading the whole copy on 6.8.2 would undo 6.8.2's
# own species changes (base stats, tutor lists, abilities, evolutions).
# Cody (2026-10-05): keep 6.8.2's data and apply only KIF's six changes:
#   * Dialga, Palkia: catch rate 30 -> 3
#   * Ferroseed, Ferrothorn: Steel/Grass -> Grass/Steel
#   * Phantump: Grass/Ghost -> Ghost/Grass
#     (type order matters for fusions: a head gives its first type)
#   * Goldeen, Seaking: Waterfall instead of Aqua Tail at Lv 32
# Applied after the game loads its data (KIF::DataLoad).
#===============================================================================
module KIF
  module SpeciesTweaks
    CATCH_RATE = { :DIALGA => 3, :PALKIA => 3 }
    TYPES      = { :FERROSEED => [:GRASS, :STEEL], :FERROTHORN => [:GRASS, :STEEL],
                   :PHANTUMP  => [:GHOST, :GRASS] }
    MOVE_SWAP  = { :GOLDEEN => [32, :AQUATAIL, :WATERFALL], :SEAKING => [32, :AQUATAIL, :WATERFALL] }

    # Original values, kept so the module can be turned off again
    @saved = nil
    @applied = false

    def self.save_originals
      data = GameData::Species::DATA
      @saved = { :catch => {}, :types => {}, :moves => {} }
      CATCH_RATE.each_key { |id| sp = data[id] and @saved[:catch][id] = sp.instance_variable_get(:@catch_rate) }
      TYPES.each_key { |id| sp = data[id] and @saved[:types][id] = [sp.instance_variable_get(:@type1), sp.instance_variable_get(:@type2)] }
      MOVE_SWAP.each_key { |id| sp = data[id] and @saved[:moves][id] = Marshal.load(Marshal.dump(sp.instance_variable_get(:@moves))) }
    end

    def self.apply
      data = GameData::Species::DATA
      save_originals if @saved.nil?
      CATCH_RATE.each do |id, rate|
        sp = data[id] or next
        sp.instance_variable_set(:@catch_rate, rate)
      end
      TYPES.each do |id, (t1, t2)|
        sp = data[id] or next
        sp.instance_variable_set(:@type1, t1)
        sp.instance_variable_set(:@type2, t2)
      end
      MOVE_SWAP.each do |id, (lvl, old_move, new_move)|
        sp = data[id] or next
        moves = sp.instance_variable_get(:@moves)
        next unless moves.is_a?(Array)
        moves.each { |m| m[1] = new_move if m[0] == lvl && m[1] == old_move }
      end
      @applied = true
    end

    def self.revert
      return unless @saved && @applied
      data = GameData::Species::DATA
      @saved[:catch].each { |id, v| sp = data[id] and sp.instance_variable_set(:@catch_rate, v) }
      @saved[:types].each { |id, (t1, t2)| sp = data[id] and (sp.instance_variable_set(:@type1, t1); sp.instance_variable_set(:@type2, t2)) }
      @saved[:moves].each { |id, v| sp = data[id] and sp.instance_variable_set(:@moves, Marshal.load(Marshal.dump(v))) }
      @applied = false
    end

    def self.applied?; @applied; end

    # Module Pokémon & Fusion: applied while it is active, undone while Off
    def self.sync(active)
      return unless defined?(GameData::Species::DATA) && !GameData::Species::DATA.empty?
      active ? (apply unless @applied) : revert
    end
  end
end

KIF::DataLoad.after_load_all("KIF species tweaks") { KIF::SpeciesTweaks.apply }
KIF::Modules.watch(:pokemon) { |active| KIF::SpeciesTweaks.sync(active) } if defined?(KIF::Modules)
