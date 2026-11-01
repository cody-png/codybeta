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
#    type chart with nil. The guard sits here, outside any module, so it also
#    holds with the Battles module Off (Mechanics.rb's wrapper of the same
#    method is gated).
module Effectiveness
  class << self
    alias kif_bc_calculate_one calculate_one unless method_defined?(:kif_bc_calculate_one)

    def calculate_one(attack_type, defend_type)
      return NORMAL_EFFECTIVE_ONE if defend_type.nil?
      return kif_bc_calculate_one(attack_type, defend_type)
    end
  end
end

# 4. PIF's switch AI asks a benched Pokémon (not in battle) for
#    hasActiveAbility?, which only battlers have. Off the field an ability is
#    simply the one it has.
class Pokemon
  def hasActiveAbility?(check_ability, *_args)
    return hasAbility?(check_ability)
  end unless method_defined?(:hasActiveAbility?)
end

# 5. Quash (PIF's 007_Move_Effects_100-17F.rb:808 and :826): the loops over
#    @battle.battlers read b.effects on every slot, and a side that is smaller
#    than the other (a 3v3 where one side has only 2 Pokemon) leaves nil
#    slots, so using Quash ended the battle in the crash handler. Copy of
#    6.8.2's two methods with `next if !b`. Date: 2026-11-01.
KIF.guard_base("011_Battle/002_Move/007_Move_Effects_100-17F.rb", 3403102880,
               "PokeBattle_Move_11E (Quash)")

class PokeBattle_Move_11E < PokeBattle_Move
  def kif_highest_quash
    highestQuash = 0
    @battle.battlers.each do |b|
      next if !b || b.effects[PBEffects::Quash] <= highestQuash
      highestQuash = b.effects[PBEffects::Quash]
    end
    return highestQuash
  end

  def pbFailsAgainstTarget?(user, target)
    return true if pbMoveFailedTargetAlreadyMoved?(target)
    # Target isn't going to use a move
    oppMove = @battle.choices[target.index][2]
    if !oppMove
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    # Target is already maximally Quashed and will move last anyway
    highestQuash = kif_highest_quash
    if highestQuash > 0 && target.effects[PBEffects::Quash] == highestQuash
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    # Target was already going to move last
    if highestQuash == 0 && @battle.pbPriority.last.index == target.index
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::Quash] = kif_highest_quash + 1
    target.effects[PBEffects::MoveNext] = false
    @battle.pbDisplay(_INTL("{1}'s move was postponed!", target.pbThis))
  end
end

# 6. A default weather of Harsh Sun or Heavy Rain with nobody holding
#    Desolate Land / Primordial Sea: pbStartWeather ends by calling
#    pbEndPrimordialWeather, which ends the weather and starts the default
#    weather again, which calls it again, until the stack runs out. Only a
#    battle rule can set such a default; the weather now ends once, as
#    Primordial weather without its Pokemon always does.
class PokeBattle_Battle
  alias kif_bc_pbEndPrimordialWeather pbEndPrimordialWeather unless method_defined?(:kif_bc_pbEndPrimordialWeather)

  def pbEndPrimordialWeather
    default = @field.defaultWeather
    return kif_bc_pbEndPrimordialWeather unless default == :HarshSun || default == :HeavyRain
    @field.defaultWeather = :None
    begin
      return kif_bc_pbEndPrimordialWeather
    ensure
      @field.defaultWeather = default
    end
  end
end

# 7. A wild battle whose foe side has nobody able (a scripted wild battle with
#    a fainted foe): pbAbleTeamCounts is empty, so pbEnsureParticipants set
#    the foe side size to nil and the battle failed later on a nil. It stops
#    with PIF's own "battle isn't possible" error instead.
class PokeBattle_Battle
  alias kif_bc_pbEnsureParticipants pbEnsureParticipants unless method_defined?(:kif_bc_pbEnsureParticipants)

  def pbEnsureParticipants
    if wildBattle? && pbAbleTeamCounts(1)[0].to_i == 0
      raise _INTL("Couldn't reduce battle size any further, battle isn't possible")
    end
    return kif_bc_pbEnsureParticipants
  end
end

# 8. A Pokemon with Shields Down whose form swap lowers max HP (Triple
#    Celestial 174 -> 144) fainted when its HP dropped from above half to
#    almost nothing in one write outside battle: calc_stats keeps the damage
#    taken, so 3 HP of 174 became 0 of 144. A swap alone never faints it.
class Pokemon
  alias kif_bc_checkHPRelatedFormChange checkHPRelatedFormChange unless method_defined?(:kif_bc_checkHPRelatedFormChange)

  def checkHPRelatedFormChange(*args)
    before = @hp
    ret = kif_bc_checkHPRelatedFormChange(*args)
    @hp = 1 if before.to_i > 0 && @hp.to_i <= 0
    return ret
  end
end
