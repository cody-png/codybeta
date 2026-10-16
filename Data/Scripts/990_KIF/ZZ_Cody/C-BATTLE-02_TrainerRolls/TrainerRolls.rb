#===============================================================================
# C-BATTLE-02 – Trainer teams keep their rolls (2026-10-11)
# PIF rolls a trainer's Pokémon afresh every battle: the personal ID decides
# the ability when the trainer file doesn't (a Ralts fusion had Synchronize
# the first time and not in the rematch), and KIF's Shiny Trainer Pokémon
# roll again too. The first fight rolls; the result is saved per trainer
# (type + name + version) in the save and put back on every later fight,
# slot by slot (a rematch that evolves a Pokémon keeps its ability slot).
# Module: Battles & Challenges.
#===============================================================================
class PokemonGlobalMetadata
  attr_writer :kif_trainer_rolls
  def kif_trainer_rolls
    @kif_trainer_rolls ||= {}
    return @kif_trainer_rolls
  end
end

module KIF
  module TrainerRolls
    # what a fight rolls at random (the rest comes from the trainer file)
    FIELDS = [:@personalID, :@ability_index, :@ability, :@shiny, :@debug_shiny, :@natural_shiny,
              :@shinyValue, :@shinyR, :@shinyG, :@shinyB, :@shinyKRS, :@shinyimprovpif,
              :@kif_filter_roll, :@head_shiny, :@body_shiny]
    LIMIT = 400   # trainers remembered per save (oldest dropped)

    def self.key(tr_type, tr_name, tr_version)
      return "#{tr_type}|#{tr_name}|#{tr_version.to_i}"
    end

    def self.store
      return nil unless $PokemonGlobal && $PokemonGlobal.respond_to?(:kif_trainer_rolls)
      return $PokemonGlobal.kif_trainer_rolls
    end

    def self.snapshot(pkmn)
      return FIELDS.map { |f| pkmn.instance_variable_defined?(f) ? pkmn.instance_variable_get(f) : nil }
    end

    def self.restore(pkmn, vals)
      FIELDS.each_with_index do |f, i|
        v = vals[i]
        if v.nil?
          pkmn.remove_instance_variable(f) if pkmn.instance_variable_defined?(f)
        else
          pkmn.instance_variable_set(f, v)
        end
      end
    end

    # Called with the trainer a fight just built
    def self.apply(trainer, k)
      st = store
      return trainer unless st && trainer && trainer.respond_to?(:party)
      rolls = st[k]
      if rolls.is_a?(Array)
        trainer.party.each_with_index do |pkmn, i|
          next unless pkmn && rolls[i].is_a?(Array)
          restore(pkmn, rolls[i])
          pkmn.calc_stats
        end
        # new slots (a bigger rematch team) are added to the record
        if trainer.party.length > rolls.length
          (rolls.length...trainer.party.length).each { |i| rolls[i] = trainer.party[i] ? snapshot(trainer.party[i]) : nil }
        end
      else
        st[k] = trainer.party.map { |p| p ? snapshot(p) : nil }
        if st.length > LIMIT
          st.keys.first(st.length - LIMIT).each { |old| st.delete(old) }
        end
      end
      return trainer
    rescue => e
      KIF.log("Trainer rolls failed for #{k}: #{e.class}: #{e.message}")
      return trainer
    end
  end
end

# The trainer is tagged with its key here; the rolls are applied when the
# battle picks the party up (onTrainerPartyLoad), after KIF's own trainer
# shiny roll (F-SHINY-02) has run, so that roll is kept too.
alias kif_rolls_pbLoadTrainer pbLoadTrainer unless defined?(kif_rolls_pbLoadTrainer)
def pbLoadTrainer(tr_type, tr_name, tr_version = 0)
  trainer = kif_rolls_pbLoadTrainer(tr_type, tr_name, tr_version)
  if trainer && !(defined?(KIF::SelfBattle) && KIF::SelfBattle.active)
    trainer.instance_variable_set(:@kif_roll_key, KIF::TrainerRolls.key(tr_type, tr_name, tr_version))
  end
  return trainer
end

Events.onTrainerPartyLoad += proc { |_sender, e|
  trainer = e.is_a?(Array) ? e[0] : e
  next if defined?(KIF.loading_partner) && KIF.loading_partner
  next if !trainer || !trainer.instance_variable_defined?(:@kif_roll_key)
  next if $Trainer && trainer.equal?($Trainer)
  KIF::TrainerRolls.apply(trainer, trainer.instance_variable_get(:@kif_roll_key))
}
