#===============================================================================
# SCOPE-02 – PIF fix: Chip Away, Sacred Sword and Darkest Lariat ignore the
# target's evasion again (2026-10-23)
# PokeBattle_Move_0A9 (011_Battle/002_Move/006_Move_Effects_080-0FF.rb) put its
# evasion reset in pbCalcAccuracyMultipliers, which the battle never calls
# (it calls pbCalcAccuracyModifiers), and that body used a name it doesn't
# have. Against Double Team or Minimize these moves missed like any other.
# Found by the kit's hook sweep (416).
#===============================================================================
class PokeBattle_Move_0A9 < PokeBattle_Move
  def pbCalcAccuracyModifiers(user, target, modifiers)
    super
    modifiers[:evasion_stage] = 0
  end
end
