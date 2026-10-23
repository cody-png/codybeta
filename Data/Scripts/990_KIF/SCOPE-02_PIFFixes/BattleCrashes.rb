#===============================================================================
# SCOPE-02 – PIF fixes: battle crashes found by the trainer sweep (2026-10-22)
# All four are in PIF 6.8.2's own battle code; KIF's doubles/triples and
# Auto-Battle (PIF's AI choosing for the player) make them easier to reach.
#===============================================================================

# 1. Synchronize under Safeguard: PIF's check reads `user`, which this method
#    doesn't have (NameError). Safeguard blocks unless the Synchronize
#    Pokémon (target) has Infiltrator; then the other checks run as before.
class PokeBattle_Battler
  alias kif_bc_pbCanSynchronizeStatus? pbCanSynchronizeStatus? unless method_defined?(:kif_bc_pbCanSynchronizeStatus?)

  def pbCanSynchronizeStatus?(newStatus, target)
    sg = pbOwnSide.effects[PBEffects::Safeguard]
    return kif_bc_pbCanSynchronizeStatus?(newStatus, target) if sg <= 0
    return false unless target && target.hasActiveAbility?(:INFILTRATOR)
    begin
      pbOwnSide.effects[PBEffects::Safeguard] = 0   # already decided above
      return kif_bc_pbCanSynchronizeStatus?(newStatus, target)
    ensure
      pbOwnSide.effects[PBEffects::Safeguard] = sg
    end
  end
end

# 2. Sea of Fire (Grass Pledge + Fire Pledge): the end of round calls
#    @battle.pbCommonAnimation inside the battle itself, where @battle is nil.
class PokeBattle_Battle
  alias kif_bc_pbEndOfRoundPhase pbEndOfRoundPhase unless method_defined?(:kif_bc_pbEndOfRoundPhase)

  def pbEndOfRoundPhase
    @battle ||= self
    return kif_bc_pbEndOfRoundPhase
  end
end

# 3. A Pokémon with no type (pure Fire after Burn Up): PIF's AI looks up the
#    type chart with nil. Fixed in KIF's own wrapper of that method (the
#    AI's hottest one): F-BATTLE-06_Mechanics/Mechanics.rb calculate_one.

# 4. PIF's switch AI asks a benched Pokémon (not in battle) for
#    hasActiveAbility?, which only battlers have. Off the field an ability is
#    simply the one it has.
class Pokemon
  def hasActiveAbility?(check_ability, *_args)
    return hasAbility?(check_ability)
  end unless method_defined?(:hasActiveAbility?)
end
