#===============================================================================
# F-BATTLE-03 (part) – Damage Variance toggle
# Source: KIF 0.20.7 011_Battle/002_Move/003_Move_Usage_Calculations.rb:416
#
# "Damage Variance" (damage_variance, per-save, default On). Off: the random
# 85-100% damage roll is skipped (always 100%). KIF also skipped it while the
# Endgame Challenge (switch 850) is active.
#
# Implementation: PIF's roll is `85 + @battle.pbRandom(16)`, the only
# pbRandom call in pbCalcDamageMultipliers (checked for 6.8.2). While that
# method runs with variance off, pbRandom(16) returns 15 -> 100%. This avoids
# copying the 150-line damage method.
# The Powerful AI part of F-BATTLE-03 (DemICE) is not ported yet.
#===============================================================================
KIF::Options.define(:damage_variance, 1, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Damage Variance"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.damage_variance },
                 proc { |value| $PokemonSystem.damage_variance = value },
                 [_INTL("Damage Variance is disabled."), _INTL("Damage Variance is enabled.")])
}

KIF.guard_base("011_Battle/002_Move/003_Move_Usage_Calculations.rb", 1637283329,
               "PokeBattle_Move#pbCalcDamageMultipliers (pbRandom(16) roll)")

class PokeBattle_Battle
  attr_accessor :kif_no_damage_roll

  alias kif_pbRandom pbRandom unless method_defined?(:kif_pbRandom)

  def pbRandom(x)
    return x - 1 if @kif_no_damage_roll && x == 16
    return kif_pbRandom(x)
  end
end

class PokeBattle_Move
  alias kif_pbCalcDamageMultipliers pbCalcDamageMultipliers unless method_defined?(:kif_pbCalcDamageMultipliers)

  def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    no_roll = $PokemonSystem.damage_variance != 1 || KIF.endgame_challenge_active?
    return kif_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers) unless no_roll
    old = @battle.kif_no_damage_roll
    @battle.kif_no_damage_roll = true
    begin
      return kif_pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
    ensure
      @battle.kif_no_damage_roll = old
    end
  end
end
