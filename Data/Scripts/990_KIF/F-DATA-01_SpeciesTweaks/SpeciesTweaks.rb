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

    def self.apply
      data = GameData::Species::DATA
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
    end
  end
end

KIF::DataLoad.after_load_all("KIF species tweaks") { KIF::SpeciesTweaks.apply }
