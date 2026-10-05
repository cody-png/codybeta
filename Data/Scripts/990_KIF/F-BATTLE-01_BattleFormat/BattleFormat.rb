#===============================================================================
# F-BATTLE-01 – Battle format 1v1 / 2v2 / 3v3 for wild and/or trainer battles
# Source: KIF 0.20.7 "Wild Battles" option (force_double_wild,
#   012_Overworld/002_Battle triggering/003_Overworld_WildEncounters.rb:216-236)
#
# "Battle Format" (force_double_wild – KIF's name, so old KIF saves keep their
# value): 1v1 / 2v2 / 3v3.
# "Format Applies To" (battle_format_scope, new – Cody 2026-10-04):
#   Wild     – KIF behaviour: random wild encounters (grass, caves, fishing,
#              Headbutt/Rock Smash/Sweet Scent) bring 2 or 3 wild Pokémon.
#              Needs 2 / 3 able Pokémon in the party, not in the Safari Zone
#              or when the game forces a single battle. Scripted wild battles
#              (legendaries etc.) are untouched.
#   Trainers – trainer battles without a scripted size use 2v2 / 3v3. PIF's
#              pbEnsureParticipants shrinks the battle if either side has
#              too few Pokémon. (PIF 6.8.2's own "Battle type" option does
#              the same but only in New Game+.)
#   Both
#===============================================================================
KIF::Options.define(:force_double_wild, 0, :save)
KIF::Options.define(:battle_format_scope, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Battle Format"), [_INTL("1v1"), _INTL("2v2"), _INTL("3v3")],
                 proc { $PokemonSystem.force_double_wild },
                 proc { |value| $PokemonSystem.force_double_wild = value },
                 [_INTL("Battles are 1v1 (unless the game says otherwise)"),
                  _INTL("Battles in 2v2 when possible"),
                  _INTL("Battles in 3v3 'cause it's cool")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Format Applies To"), [_INTL("Wild"), _INTL("Trainers"), _INTL("Both")],
                 proc { $PokemonSystem.battle_format_scope },
                 proc { |value| $PokemonSystem.battle_format_scope = value },
                 [_INTL("Battle Format applies to wild encounters"),
                  _INTL("Battle Format applies to trainer battles"),
                  _INTL("Battle Format applies to wild and trainer battles")])
}

module KIF
  @random_encounter = false
  class << self
    attr_accessor :random_encounter
  end

  def self.battle_format
    return $PokemonSystem ? ($PokemonSystem.force_double_wild || 0) : 0
  end

  def self.format_for_wild?
    return battle_format > 0 && [0, 2].include?($PokemonSystem.battle_format_scope)
  end

  def self.format_for_trainers?
    return battle_format > 0 && [1, 2].include?($PokemonSystem.battle_format_scope)
  end

  def self.with_random_encounter
    old = @random_encounter
    @random_encounter = true
    yield
  ensure
    @random_encounter = old
  end
end

#-------------------------------------------------------------------------------
# Wild: random encounters only (pbBattleOnStepTaken / pbEncounter)
#-------------------------------------------------------------------------------
alias kif_pbBattleOnStepTaken pbBattleOnStepTaken unless defined?(kif_pbBattleOnStepTaken)
def pbBattleOnStepTaken(*args)
  KIF.with_random_encounter { kif_pbBattleOnStepTaken(*args) }
end

alias kif_pbEncounter pbEncounter unless defined?(kif_pbEncounter)
def pbEncounter(*args)
  ret = nil
  KIF.with_random_encounter { ret = kif_pbEncounter(*args) }
  return ret
end

class PokemonEncounters
  alias kif_have_double_wild_battle? have_double_wild_battle? unless method_defined?(:kif_have_double_wild_battle?)

  def have_double_wild_battle?
    return true if kif_have_double_wild_battle?
    return false unless KIF.random_encounter && KIF.format_for_wild?
    return false if $PokemonTemp.forceSingleBattle
    return false if pbInSafari?
    return false if $Trainer.able_pokemon_count <= 1
    return true
  end
end

# A random double encounter becomes a triple when the format is 3v3: a third
# Pokémon is rolled from the same encounter table (KIF: have_triple_wild_battle?).
alias kif_pbDoubleWildBattle pbDoubleWildBattle unless defined?(kif_pbDoubleWildBattle)
def pbDoubleWildBattle(species1, level1, species2, level2, *rest)
  if KIF.random_encounter && KIF.format_for_wild? && KIF.battle_format >= 2 &&
     !$PokemonTemp.forceSingleBattle && !pbInSafari? && $Trainer.able_pokemon_count > 2 &&
     $PokemonTemp.encounterType
    enc3 = $PokemonEncounters.choose_wild_pokemon($PokemonTemp.encounterType)
    enc3 = EncounterModifier.trigger(enc3) if enc3
    if enc3
      return pbTripleWildBattle(species1, level1, species2, level2, enc3[0], enc3[1], *rest)
    end
  end
  return kif_pbDoubleWildBattle(species1, level1, species2, level2, *rest)
end

#-------------------------------------------------------------------------------
# Trainers
#-------------------------------------------------------------------------------
alias kif_pbPrepareBattle pbPrepareBattle unless defined?(kif_pbPrepareBattle)
def pbPrepareBattle(battle)
  kif_pbPrepareBattle(battle)
  rules = $PokemonTemp.battleRules
  return unless battle.trainerBattle? && KIF.format_for_trainers?
  return unless rules["size"].nil? && rules["birdboss"].nil?
  battle.setBattleMode(["1v1", "2v2", "3v3"][KIF.battle_format])
end
