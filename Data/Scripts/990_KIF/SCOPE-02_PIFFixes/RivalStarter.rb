#===============================================================================
# SCOPE-02 – PIF fix: the Johto/Hoenn/Sinnoh starter labs (2026-10-22)
# Their rival event (Map551/552/593 ev21) still calls the old
# setRivalStarter(s1, s2, s3, choice) with three species numbers and the
# player's pick; PIF 6.8.2 only has setRivalStarter(index1, index2), so Blue
# walking up crashed with ArgumentError. The old form works again: the rival
# gets the two starters the player didn't pick, fused (as PIF 6.8.2 does).
#===============================================================================
alias kif_rs_setRivalStarter setRivalStarter unless defined?(kif_rs_setRivalStarter)

def setRivalStarter(*args)
  return kif_rs_setRivalStarter(*args) unless args.length == 4
  starters = args[0, 3].map { |s| GameData::Species.get(s).id_number }
  starters.delete_at(args[3].to_i.clamp(0, 2))
  rival = if starters.any? { |s| s > NB_POKEMON }   # already a fusion: keep it
            starters[0]
          else
            getFusionSpecies(starters[0], starters[1]).id_number
          end
  pbSet(VAR_RIVAL_STARTER, rival)
  $game_switches[SWITCH_DEFINED_RIVAL_STARTER] = true
  return rival
end

#===============================================================================
# 2.0.7 – a rival starter that is no species (a player's save had 662302,
# "B1149H478": its custom lab ran with a different species count) crashed every
# rival evolve script and the rival battle. Such a number is rebuilt from the
# save's own choices: the Custom lab's formula (map 659: body var 213, head var
# 212), else the two starters the player didn't pick (fixRivalStarter).
#===============================================================================
module KIF
  module RivalStarter
    # a one- or two-part species (a rival is never a triple fusion). Symbols are
    # checked by name: Species.get turns unknown ones into Pikachu.
    # shortcut: a number from that other build that lands inside KIF's range
    # reads as another fusion; only out-of-range numbers are caught.
    def self.valid?(v)
      if v.is_a?(Symbol)
        return $1.to_i.between?(1, NB_POKEMON) && $2.to_i.between?(1, NB_POKEMON) if v.to_s =~ /\AB(\d+)H(\d+)\z/
        return GameData::Species::DATA.key?(v) && GameData::Species.get(v).id_number <= NB_POKEMON
      end
      return v.is_a?(Integer) && v.between?(1, NB_POKEMON * (NB_POKEMON + 1))
    rescue
      false
    end

    # the rival starter number, rebuilt first if it is no species
    def self.repair
      v = old = pbGet(VAR_RIVAL_STARTER)
      return v if v == 0 || valid?(v)
      body, head = pbGet(213), pbGet(212)
      if $game_switches[SWITCH_CUSTOM_STARTERS] && [body, head].all? { |x| x.is_a?(Integer) && x.between?(1, NB_POKEMON) }
        v = body * NB_POKEMON + head
      else
        pbSet(VAR_RIVAL_STARTER, 0)
        fixRivalStarter
        v = pbGet(VAR_RIVAL_STARTER)
      end
      KIF.log("Rival starter #{old.inspect} was no species; rebuilt as #{v}") rescue nil
      pbSet(VAR_RIVAL_STARTER, v)
      return v
    end
  end
end

[:evolveBody, :evolveHead].each do |m|
  old = :"kif_rs_#{m}"
  next if Object.private_method_defined?(old) || Object.method_defined?(old)
  Object.send(:alias_method, old, m)
  Object.send(:define_method, m) do |species|
    species = KIF::RivalStarter.repair unless KIF::RivalStarter.valid?(species)
    send(old, species)
  end
  Object.send(:private, m)
end

# the E4 rematch champion reads variable 250 straight into Pokemon.new
if Object.private_method_defined?(:get_rival_starter) && !Object.private_method_defined?(:kif_rs_get_rival_starter)
  alias kif_rs_get_rival_starter get_rival_starter
  def get_rival_starter(*args)
    KIF::RivalStarter.repair
    return kif_rs_get_rival_starter(*args)
  end
end

module GameData
  class Trainer
    alias kif_rs_replace_species_with_placeholder replace_species_with_placeholder unless method_defined?(:kif_rs_replace_species_with_placeholder) || private_method_defined?(:kif_rs_replace_species_with_placeholder)

    def replace_species_with_placeholder(species)
      KIF::RivalStarter.repair if species == Settings::RIVAL_STARTER_PLACEHOLDER_SPECIES
      return kif_rs_replace_species_with_placeholder(species)
    end
  end
end
