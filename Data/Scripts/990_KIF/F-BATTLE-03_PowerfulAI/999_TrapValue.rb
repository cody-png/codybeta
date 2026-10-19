#===============================================================================
# F-BATTLE-03 – Value of trapping moves for both battle AIs (2026-10-14)
#
# Mean Look / Block / Spider Web (function "0EF", status moves) only change
# a foe's options, so neither AI gave them any value: PIF's AI scored them
# like any status move (005_AI_Move_EffectScores.rb:2064, -90 if already
# trapped) and DemICE's AI has no case of its own for them. Trapping now
# earns TRAP_BONUS when it sets something up:
#   * the user or an ally knows Perish Song and the foe isn't counting down;
#   * the foe takes damage every turn: badly poisoned, Leech Seed, Curse,
#     Nightmare;
#   * the foe can't really hurt the user: its best estimated damage on the
#     user is under 15% of the user's HP (or it is immune to all its attacks).
# No bonus when the foe can't be trapped or kept in: Ghost type, Shed Shell,
# already trapped (Mean Look, binding moves, Ingrain, Fairy Lock, Shadow Tag
# and the like), or it knows U-turn / Volt Switch / Baton Pass / Parting Shot
# / Teleport.
# Loads after 999_Dispatch.rb, so it wraps the AI switch: the bonus is added
# to whichever AI is in charge (DemICE's answer is a change to the score,
# PIF's the score itself; both just get TRAP_BONUS more).
#===============================================================================
class PokeBattle_AI
  KIF_TRAP_BONUS = 40
  KIF_TRAP_ESCAPE_CODES = ["0EE", "0ED", "151", "0EA"]   # U-turn/Volt Switch, Baton Pass, Parting Shot, Teleport

  alias kif_trap_pbGetMoveScoreFunctionCode pbGetMoveScoreFunctionCode unless method_defined?(:kif_trap_pbGetMoveScoreFunctionCode)

  def pbGetMoveScoreFunctionCode(score, move, user, target, skill = 100)
    ret = kif_trap_pbGetMoveScoreFunctionCode(score, move, user, target, skill)
    begin
      ret += KIF_TRAP_BONUS if move.function == "0EF" && move.statusMove? && kif_ai_trap_worth?(user, target, skill, move)
    rescue => e
      KIF.log("Trap value: #{e.class}: #{e.message}")
    end
    return ret
  end

  # Moves that still get the foe out once it's trapped (function codes). One
  # method so a mod whose trapping move stops them (DD's Block) can say so.
  def kif_ai_trap_escape_codes(user, move, target)
    return KIF_TRAP_ESCAPE_CODES
  end

  # Can the foe be kept in by Mean Look (and isn't it already)?
  def kif_ai_trappable?(target, user = nil, move = nil)
    return false if !target || target.fainted?
    return false if Settings::MORE_TYPE_EFFECTS && target.pbHasType?(:GHOST)
    return false if target.hasActiveItem?(:SHEDSHELL)
    return false if target.effects[PBEffects::MeanLook] >= 0 || target.effects[PBEffects::Trapping] > 0 ||
                    target.effects[PBEffects::Ingrain] || @battle.field.effects[PBEffects::FairyLock] > 0
    @battle.eachOtherSideBattler(target.index) do |b|
      next if !b.abilityActive?
      return false if BattleHandlers.triggerTrappingTargetAbility(b.ability, target, b, @battle)
    end
    codes = kif_ai_trap_escape_codes(user, move, target)
    return false if !codes.empty? && target.pbHasMoveFunction?(*codes)
    # Nothing to switch to: trapping changes nothing
    return false if @battle.pbAbleNonActiveCount(target.index) == 0
    return true
  end

  # Best estimated damage of the foe's attacks on the user
  def kif_ai_best_damage_on(attacker, defender, skill)
    best = 0
    attacker.eachMove do |m|
      next if !m.damagingMove?
      next if pbCheckMoveImmunity(1, m, attacker, defender, skill)
      d = pbRoughDamage(m, attacker, defender, skill, pbMoveBaseDamage(m, attacker, defender, skill))
      best = d if d > best
    end
    return best
  end

  def kif_ai_trap_worth?(user, target, skill, move = nil)
    return false if user.index == target.index || !target.opposes?(user)
    return false if !kif_ai_trappable?(target, user, move)
    # Perish Song trap
    if target.effects[PBEffects::PerishSong] == 0
      return true if user.pbHasMoveFunction?("0E5")
      user.eachAlly { |b| return true if b.pbHasMoveFunction?("0E5") }
    end
    # damage every turn
    return true if target.status == :POISON && target.effects[PBEffects::Toxic] > 0
    return true if target.effects[PBEffects::LeechSeed] >= 0
    return true if target.effects[PBEffects::Curse]
    return true if target.effects[PBEffects::Nightmare] && target.status == :SLEEP
    # the foe can't really hurt the user
    return true if kif_ai_best_damage_on(target, user, skill) < user.hp * 0.15
    return false
  end
end
