#===============================================================================
# SCOPE-02 – PIF fix: Prism Armor and Shadow Shield work against Mold Breaker
# PIF 6.8.2's PokeBattle_Move#pbCalcDamageMultipliers
# (011_Battle/002_Move/003_Move_Usage_Calculations.rb:285-298) runs the
# target's "can't be ignored" damage abilities (DamageCalcTargetAbilityNonIgnorable)
# inside its `if !@battle.moldBreaker` block, so Mold Breaker, Teravolt and
# Turboblaze ignored them. In the main games they can't be ignored. While the
# attacker has Mold Breaker this runs them after the base method. Always on
# (a bug fix). Date: 2026-10-14.
#===============================================================================
class PokeBattle_Move
  alias kif_nonig_pbCalcDamageMultipliers pbCalcDamageMultipliers unless method_defined?(:kif_nonig_pbCalcDamageMultipliers)
  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    kif_nonig_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    return if !@battle.moldBreaker || !target.abilityActive?
    BattleHandlers.triggerDamageCalcTargetAbilityNonIgnorable(target.ability,
       user, target, self, multipliers, baseDmg, type)
  end
end
