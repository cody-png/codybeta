#===============================================================================
# Battle helpers shared by several KIF features
#===============================================================================
class PokeBattle_Battle
  # KIF 002_PokeBattle_Battle.rb:293. "Really the player's Pokémon", even when
  # Auto-Battle (F-BATTLE-02) makes pbOwnedByPlayer? lie.
  def pbOwnedByPlayerSerious?(idxBattler)
    return false if opposes?(idxBattler)
    return pbGetOwnerIndexFromBattlerIndex(idxBattler) == 0
  end
end

class PokeBattle_Battler
  def pbOwnedByPlayerSerious?
    return @battle.pbOwnedByPlayerSerious?(@index)
  end
end

module KIF
  # Last Resort fails until every other move it knows has been used since it
  # came in (PokeBattle_Move_125#pbFailsAgainstTarget?, without the message).
  # Both AIs ask this so they don't pick it while it can't work.
  def self.last_resort_fails?(user, move)
    others = []
    has_it = false
    user.eachMove { |m| m.id == move.id ? (has_it = true) : (others << m.id) }
    return !has_it || others.empty? || others.any? { |id| !user.movesUsed.include?(id) }
  end

  # DemICE's Endgame Challenge (switch 850). Redefined by F-BATTLE-04
  # (002_EndgameChallenge.rb); false only if that folder is removed.
  def self.endgame_challenge_active?
    return false
  end
end

# Battle AI dispatch (F-BATTLE-03 PowerfulAI). The switch itself lives here,
# outside every module, so the mod adapter (Alpha Encounters' own AI written
# for KIF 0.20.7) still gets its answers when the Battles module is Off.
module KIF
  def self.define_ai_dispatch(cls, m, pif, demi)
    cls.send(:define_method, m) do |*args, &block|
      if KIF::PowerfulAI.on?
        send(demi, *args, &block)
      elsif Thread.current[:kif_mod_ai]
        KIF::PowerfulAI.mod_adapt(self, m, pif, args, block)
      else
        send(pif, *args, &block)
      end
    end
  end
end

# Stats follow a rule change at once (Max IVs, No-EVs, fusion stat rules):
# every party and boxed Pokémon is recalculated. PIF only recalculates on a
# level up, so the Summary and battles would show the old numbers until then.
module KIF
  def self.recalc_all_stats
    return unless $Trainer
    begin
      $Trainer.party.each { |p| p.calc_stats if p && !p.egg? }
      if $PokemonStorage
        $PokemonStorage.boxes.each do |box|
          box.pokemon.each { |p| p.calc_stats if p && !p.egg? }
        end
      end
    rescue => e
      KIF.log("recalc_all_stats failed: #{e.class}: #{e.message}")
    end
  end
end

# KIF 0.20.7's hasActiveAbility? takes a third argument (mold_broken, from
# DemICE's AI); mods written for KIF pass it (GhostItem Splicers). The
# 3-argument form is always accepted, whatever the Battles module does.
class PokeBattle_Battler
  alias kif_core_hasActiveAbility? hasActiveAbility? unless method_defined?(:kif_core_hasActiveAbility?)
  def hasActiveAbility?(check_ability, ignore_fainted = false, mold_broken = false)
    return false if mold_broken
    return kif_core_hasActiveAbility?(check_ability, ignore_fainted)
  end
end

# Stand-in battlers (DemICE's switch-in scoring, Auto-Battle's move scoring)
# are built with an active battler's index. 6.8.2's PokeBattle_Battler.new /
# pbInitEffects then clear what every real battler aims at that index
# (002_Battler_Initialize.rb: Attract, Lock-On, Mean Look, Sky Drop, binding
# moves), so only scoring a switch-in freed a trapped or infatuated Pokémon.
# The real battlers' effects are put back once the stand-in exists.
module KIF
  def self.keep_battler_effects(battle)
    saved = []
    (battle.battlers rescue []).each { |b| saved << [b, b.effects.dup] if b && b.effects }
    return yield
  ensure
    (saved || []).each { |b, eff| b.effects.replace(eff) }
  end
end

# Shared by both battle AIs (DemICE's, F-BATTLE-03, and PIF's, fixed in
# SCOPE-02_PIFFixes/BattleAI.rb). KIF's Frostbite / Drowsy options
# (F-BATTLE-06) keep the status names :FROZEN / :SLEEP, so the AIs ask here
# whether a Pokémon is really frozen / fully asleep.
class PokeBattle_AI
  # Frozen and unable to act (not Frostbite)
  def kif_ai_frozen?(b)
    return b.status == :FROZEN && !KIF::Mechanics.frostbite_in_battle?
  end

  # Asleep and unable to act (not Drowsy)
  def kif_ai_sleeping?(b)
    return b.status == :SLEEP && !KIF::Mechanics.drowsy_in_battle?
  end

  # Frostbite halves special moves, Drowsy halves every move; Guts ignores
  # both (Mechanics.rb pbCalcDamageMultipliers)
  def kif_ai_status_damage_mult(move, user, type)
    return 1.0 if user.hasActiveAbility?(:GUTS)
    return 0.5 if user.status == :FROZEN && KIF::Mechanics.frostbite_in_battle? && move.specialMove?(type)
    return 0.5 if user.status == :SLEEP && KIF::Mechanics.drowsy_in_battle?
    return 1.0
  end

  # The user's damage ability. Handlers that read the hit itself (critical
  # hit, effectiveness, move order) can't be run before the attack: Tinted
  # Lens and the -ate abilities are worked out here, Analytic and Sniper are
  # left out.
  def kif_ai_user_damage_ability(user, target, move, type, typeMod, mults, baseDmg)
    return if !user.abilityActive?
    case user.ability_id
    when :ANALYTIC, :SNIPER
      # move order / critical hits aren't known yet
    when :TINTEDLENS
      mults[:final_damage_multiplier] *= 2 if Effectiveness.resistant?(typeMod)
    when :AERILATE, :PIXILATE, :REFRIGERATE, :GALVANIZE
      mults[:base_damage_multiplier] *= 1.2 if move.type == :NORMAL && type && type != :NORMAL
    else
      BattleHandlers.triggerDamageCalcUserAbility(user.ability, user, target, move, mults, baseDmg, type)
    end
  end

  # The target's damage ability (without Mold Breaker). Filter / Solid Rock
  # read the hit's effectiveness, so they are worked out from typeMod.
  def kif_ai_target_damage_ability(user, target, move, type, typeMod, mults, baseDmg)
    return if !target.abilityActive?
    if [:FILTER, :SOLIDROCK].include?(target.ability_id)
      mults[:final_damage_multiplier] *= 0.75 if Effectiveness.super_effective?(typeMod)
    else
      BattleHandlers.triggerDamageCalcTargetAbility(target.ability, user, target, move, mults, baseDmg, type)
    end
  end

  # Prism Armor / Shadow Shield: can't be ignored, so they count with Mold
  # Breaker too (SCOPE-02_PIFFixes/NonIgnorableAbilities.rb fixes the game's own
  # damage calc the same way).
  def kif_ai_target_nonignorable(user, target, move, type, typeMod, mults, baseDmg)
    return if !target.abilityActive?
    if target.ability_id == :PRISMARMOR
      mults[:final_damage_multiplier] *= 0.75 if Effectiveness.super_effective?(typeMod)
    else
      BattleHandlers.triggerDamageCalcTargetAbilityNonIgnorable(target.ability, user, target, move, mults, baseDmg, type)
    end
  end
end
