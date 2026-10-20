#===============================================================================
# SCOPE-02 – PIF fix: Comatose works for any Pokémon that has it
# PIF 6.8.2's two Comatose handlers (011_Battle/003_BattleHandlers_Abilities.rb:
# 117-122 and 178-182) only work for Komala. The Randomizer's random abilities
# and mods (KIF-ER, Megas) give Comatose to other Pokémon, which could then
# still be poisoned or put to sleep and never counted as asleep. Always on
# (a bug fix). Date: 2026-10-19.
#===============================================================================
BattleHandlers::StatusCheckAbilityNonIgnorable.add(:COMATOSE,
  proc { |ability, battler, status|
    next true if status.nil? || status == :SLEEP
  }
)

BattleHandlers::StatusImmunityAbilityNonIgnorable.add(:COMATOSE,
  proc { |ability, battler, status|
    next true
  }
)
