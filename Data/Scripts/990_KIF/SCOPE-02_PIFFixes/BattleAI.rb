#===============================================================================
# SCOPE-02 – PIF 6.8.2's battle AI fixes (Options > Battles > Battle AI: PIF,
# and whenever the Battles module is Off)
#
# PIF's AI is saved as kif_pif_<method> by F-BATTLE-03 (000_PowerfulAI.rb)
# and called by the AI dispatch; the two methods below replace those copies
# (copied from 011_Battle/004_AI/004_AI_Move.rb:157-254 and
# 006_AI_Move_Utilities.rb:261-559, lines marked "KIF"). Fixed 2026-10-14:
#   * damage estimate: Mold Breaker was checked on the target instead of the
#     user; the user/target ability blacklists compared move.id with ability
#     ids (never matched), so Tinted Lens, Sniper, Filter and Solid Rock read
#     the previous hit's effectiveness / critical hit; Prism Armor and Shadow
#     Shield were never counted. Shared helpers: 000_Core/004_KIF_BattleHelpers.rb.
#   * status moves into an ability that absorbs or blocks them (Thunder Wave
#     into Volt Absorb, Will-O-Wisp into Flash Fire, Spore into Sap Sipper /
#     Overcoat, Sing into Soundproof, Magic Bounce, Prankster into Dark types,
#     Substitute) now score 0; 6.8.2 checked immunities for damaging moves only.
#   * KIF's Frostbite / Drowsy options (F-BATTLE-06): a frostbitten or drowsy
#     Pokémon is not treated as frozen / asleep, and its damage cut is counted.
#===============================================================================
KIF.guard_base("011_Battle/004_AI/004_AI_Move.rb", 1014949990, "PokeBattle_AI#pbGetMoveScore (BattleAI.rb)")
KIF.guard_base("011_Battle/004_AI/006_AI_Move_Utilities.rb", 885931834, "PokeBattle_AI#pbRoughDamage (BattleAI.rb)")

class PokeBattle_AI
  # A status move aimed at a foe that the foe's ability or Substitute stops
  def kif_pif_status_move_blocked?(move, user, target, skill)
    return false if !move.statusMove? || user.index == target.index || !target.opposes?(user)
    return true if move.canMagicCoat? && target.hasActiveAbility?(:MAGICBOUNCE)
    return true if target.effects[PBEffects::Substitute] > 0 && !move.ignoresSubstitute?(user)
    return true if Settings::MECHANICS_GENERATION >= 7 && user.hasActiveAbility?(:PRANKSTER) &&
                   target.pbHasType?(:DARK)
    if move.powderMove?
      return true if target.pbHasType?(:GRASS) || target.hasActiveItem?(:SAFETYGOGGLES)
    end
    return false if user.hasMoldBreaker?
    return true if move.powderMove? && target.hasActiveAbility?(:OVERCOAT)
    return true if move.soundMove? && target.hasActiveAbility?(:SOUNDPROOF)
    case pbRoughType(move, user, skill)
    when :FIRE     then return true if target.hasActiveAbility?(:FLASHFIRE)
    when :WATER    then return true if target.hasActiveAbility?([:DRYSKIN, :STORMDRAIN, :WATERABSORB])
    when :GRASS    then return true if target.hasActiveAbility?(:SAPSIPPER)
    when :ELECTRIC then return true if target.hasActiveAbility?([:LIGHTNINGROD, :MOTORDRIVE, :VOLTABSORB])
    end
    return false
  end

  def kif_pif_pbGetMoveScore(move, user, target, skill = 100)
    skill = PBTrainerAI.minimumSkill if skill < PBTrainerAI.minimumSkill
    score = 100
    score = pbGetMoveScoreFunctionCode(score, move, user, target, skill)

    #echoln "Move #{move.id} : score"

    # A score of 0 here means it absolutely should not be used
    return 0 if score <= 0
    # KIF fix: status moves into an ability or effect that blocks them
    # (Thunder Wave into Volt Absorb...); 6.8.2 checked damaging moves only
    return 0 if skill >= PBTrainerAI.mediumSkill && kif_pif_status_move_blocked?(move, user, target, skill)
    # KIF fix: 6.8.2 scored Last Resort like any 140-power move, so a Pokémon
    # that hadn't used its other moves yet kept choosing it and failing
    return 0 if move.function == "125" && KIF.last_resort_fails?(user, move)
    if skill >= PBTrainerAI.mediumSkill
      # Prefer damaging moves if AI has no more Pokémon or AI is less clever
      if @battle.pbAbleNonActiveCount(user.idxOwnSide) == 0
        if !(skill >= PBTrainerAI.highSkill && @battle.pbAbleNonActiveCount(target.idxOwnSide) > 0)
          if move.statusMove?
            score /= 1.5
          elsif target.hp <= target.totalhp / 2
            score *= 1.5
          end
        end
      end
      # Don't prefer attacking the target if they'd be semi-invulnerable
      if skill >= PBTrainerAI.highSkill && move.accuracy > 0 &&
        (target.semiInvulnerable? || target.effects[PBEffects::SkyDrop] >= 0)
        miss = true
        miss = false if user.hasActiveAbility?(:NOGUARD) || target.hasActiveAbility?(:NOGUARD)
        if miss && pbRoughStat(user, :SPEED, skill) > pbRoughStat(target, :SPEED, skill)
          # Knows what can get past semi-invulnerability
          if target.effects[PBEffects::SkyDrop] >= 0
            miss = false if move.hitsFlyingTargets?
          else
            if target.inTwoTurnAttack?("0C9", "0CC", "0CE") # Fly, Bounce, Sky Drop
              miss = false if move.hitsFlyingTargets?
            elsif target.inTwoTurnAttack?("0CA") # Dig
              miss = false if move.hitsDiggingTargets?
            elsif target.inTwoTurnAttack?("0CB") # Dive
              miss = false if move.hitsDivingTargets?
            end
          end
        end
        score -= 80 if miss
      end
      # Pick a good move for the Choice items
      if user.hasActiveItem?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF])
        if move.baseDamage >= 60;
          score += 60
        elsif move.damagingMove?;
          score += 30
        elsif move.function == "0F2";
          score += 70 # Trick
        else
          ; score -= 60
        end
      end
      # If user is asleep, prefer moves that are usable while asleep
      if kif_ai_sleeping?(user) && !move.usableWhenAsleep?   # KIF: not while Drowsy
        user.eachMove do |m|
          next unless m.usableWhenAsleep?
          score -= 60
          break
        end
      end
      # If user is frozen, prefer a move that can thaw the user
      if kif_ai_frozen?(user)   # KIF: Frostbite can act
        if move.thawsUser?
          score += 40
        else
          user.eachMove do |m|
            next unless m.thawsUser?
            score -= 60
            break
          end
        end
      end
      # If target is frozen, don't prefer moves that could thaw them
      if kif_ai_frozen?(target)   # KIF: Frostbite can act
        user.eachMove do |m|
          next if m.thawsUser?
          score -= 60
          break
        end
      end
    end
    # Adjust score based on how much damage it can deal
    if move.damagingMove?
      score = pbGetMoveScoreDamage(score, move, user, target, skill)
    else
      # Status moves
      # Don't prefer attacks which don't deal damage
      score -= 10
      # Account for accuracy of move
      accuracy = pbRoughAccuracy(move, user, target, skill)
      score *= accuracy / 100.0
      score = 0 if score <= 10 && skill >= PBTrainerAI.highSkill
    end
    score = score.to_i
    score = 0 if score < 0
    return score
  end
  def kif_pif_pbRoughDamage(move,user,target,skill,baseDmg)
    # Fixed damage moves
    return baseDmg if move.is_a?(PokeBattle_FixedDamageMove)
    # Get the move's type
    type = pbRoughType(move,user,skill)
    typeMod = pbCalcTypeMod(type,user,target)   # KIF
    ##### Calculate user's attack stat #####
    atk = pbRoughStat(user,:ATTACK,skill)
    if move.function=="121"   # Foul Play
      atk = pbRoughStat(target,:ATTACK,skill)
    elsif move.specialMove?(type)
      if move.function=="121"   # Foul Play
        atk = pbRoughStat(target,:SPECIAL_ATTACK,skill)
      else
        atk = pbRoughStat(user,:SPECIAL_ATTACK,skill)
      end
    end
    ##### Calculate target's defense stat #####
    defense = pbRoughStat(target,:DEFENSE,skill)
    if move.specialMove?(type) && move.function!="122"   # Psyshock
      defense = pbRoughStat(target,:SPECIAL_DEFENSE,skill)
    end
    ##### Calculate all multiplier effects #####
    multipliers = {
      :base_damage_multiplier  => 1.0,
      :attack_multiplier       => 1.0,
      :defense_multiplier      => 1.0,
      :final_damage_multiplier => 1.0
    }
    # Ability effects that alter damage
    moldBreaker = false
    # KIF fix: the user's Mold Breaker (6.8.2 checked the target's)
    if skill>=PBTrainerAI.highSkill && (user.hasMoldBreaker? || ["163", "164"].include?(move.function))
      moldBreaker = true
    end
    if skill>=PBTrainerAI.mediumSkill && user.abilityActive?
      # KIF fix: 6.8.2's blacklist compared move.id with ability ids, so it
      # never matched. Analytic / Sniper are left out; Tinted Lens and the
      # -ate abilities are worked out from this move.
      kif_ai_user_damage_ability(user,target,move,type,typeMod,multipliers,baseDmg)
    end
    if skill>=PBTrainerAI.mediumSkill && !moldBreaker
      user.eachAlly do |b|
        next if !b.abilityActive?
        BattleHandlers.triggerDamageCalcUserAllyAbility(b.ability,
           user,target,move,multipliers,baseDmg,type)
      end
    end
    if skill>=PBTrainerAI.bestSkill && !moldBreaker && target.abilityActive?
      # KIF fix: Filter / Solid Rock from this move's effectiveness (their
      # handlers read the last hit's); Prism Armor / Shadow Shield added
      kif_ai_target_damage_ability(user,target,move,type,typeMod,multipliers,baseDmg)
    end
    # Prism Armor / Shadow Shield can't be ignored, Mold Breaker or not
    if skill>=PBTrainerAI.bestSkill
      kif_ai_target_nonignorable(user,target,move,type,typeMod,multipliers,baseDmg)
    end
    if skill>=PBTrainerAI.bestSkill && !moldBreaker
      target.eachAlly do |b|
        next if !b.abilityActive?
        BattleHandlers.triggerDamageCalcTargetAllyAbility(b.ability,
           user,target,move,multipliers,baseDmg,type)
      end
    end
    # Item effects that alter damage
    # NOTE: Type-boosting gems aren't suitable for checking at the start of the
    #       round.
    if skill>=PBTrainerAI.mediumSkill && user.itemActive?
      # NOTE: These items aren't suitable for checking at the start of the
      #       round.
      itemBlacklist = [:EXPERTBELT,:LIFEORB]
      if !itemBlacklist.include?(user.item_id)
        BattleHandlers.triggerDamageCalcUserItem(user.item,
           user,target,move,multipliers,baseDmg,type)
      end
    end
    if skill>=PBTrainerAI.bestSkill && target.itemActive?
      # NOTE: Type-weakening berries aren't suitable for checking at the start
      #       of the round.
      if target.item && !target.item.is_berry?
        BattleHandlers.triggerDamageCalcTargetItem(target.item,
           user,target,move,multipliers,baseDmg,type)
      end
    end
    # Global abilities
    if skill>=PBTrainerAI.mediumSkill
      if (@battle.pbCheckGlobalAbility(:DARKAURA) && type == :DARK) ||
         (@battle.pbCheckGlobalAbility(:FAIRYAURA) && type == :FAIRY)
        if @battle.pbCheckGlobalAbility(:AURABREAK)
          multipliers[:base_damage_multiplier] *= 2 / 3.0
        else
          multipliers[:base_damage_multiplier] *= 4 / 3.0
        end
      end
    end
    # Parental Bond
    if skill>=PBTrainerAI.mediumSkill && user.hasActiveAbility?(:PARENTALBOND)
      multipliers[:base_damage_multiplier] *= 1.25
    end
    # Me First
    # TODO
    # Helping Hand - n/a
    # Charge
    if skill>=PBTrainerAI.mediumSkill
      if user.effects[PBEffects::Charge]>0 && type == :ELECTRIC
        multipliers[:base_damage_multiplier] *= 2
      end
    end
    # Mud Sport and Water Sport
    if skill>=PBTrainerAI.mediumSkill
      if type == :ELECTRIC
        @battle.eachBattler do |b|
          next if !b.effects[PBEffects::MudSport]
          multipliers[:base_damage_multiplier] /= 3
          break
        end
        if @battle.field.effects[PBEffects::MudSportField]>0
          multipliers[:base_damage_multiplier] /= 3
        end
      end
      if type == :FIRE
        @battle.eachBattler do |b|
          next if !b.effects[PBEffects::WaterSport]
          multipliers[:base_damage_multiplier] /= 3
          break
        end
        if @battle.field.effects[PBEffects::WaterSportField]>0
          multipliers[:base_damage_multiplier] /= 3
        end
      end
    end
    # Terrain moves
    if skill>=PBTrainerAI.mediumSkill
      case @battle.field.terrain
      when :Electric
        multipliers[:base_damage_multiplier] *= 1.5 if type == :ELECTRIC && user.affectedByTerrain?
      when :Grassy
        multipliers[:base_damage_multiplier] *= 1.5 if type == :GRASS && user.affectedByTerrain?
      when :Psychic
        multipliers[:base_damage_multiplier] *= 1.5 if type == :PSYCHIC && user.affectedByTerrain?
      when :Misty
        multipliers[:base_damage_multiplier] /= 2 if type == :DRAGON && target.affectedByTerrain?
      end
    end
    # Badge multipliers
    if skill>=PBTrainerAI.highSkill
      if @battle.internalBattle
        # Don't need to check the Atk/Sp Atk-boosting badges because the AI
        # won't control the player's Pokémon.
        if target.pbOwnedByPlayer?
          if move.physicalMove?(type) && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_DEFENSE
            multipliers[:defense_multiplier] *= 1.1
          elsif move.specialMove?(type) && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_SPDEF
            multipliers[:defense_multiplier] *= 1.1
          end
        end
      end
    end
    # Multi-targeting attacks
    if skill>=PBTrainerAI.highSkill
      if pbTargetsMultiple?(move,user)
        multipliers[:final_damage_multiplier] *= 0.75
      end
    end
    # Weather
    if skill>=PBTrainerAI.mediumSkill
      case @battle.pbWeather
      when :Sun, :HarshSun
        if type == :FIRE
          multipliers[:final_damage_multiplier] *= 1.5
        elsif type == :WATER
          multipliers[:final_damage_multiplier] /= 2
        end
      when :Rain, :HeavyRain
        if type == :FIRE
          multipliers[:final_damage_multiplier] /= 2
        elsif type == :WATER
          multipliers[:final_damage_multiplier] *= 1.5
        end
      when :Sandstorm
        if target.pbHasType?(:ROCK) && move.specialMove?(type) && move.function != "122"   # Psyshock
          multipliers[:defense_multiplier] *= 1.5
        end
      end
    end
    # Critical hits - n/a
    # Random variance - n/a
    # STAB
    if skill>=PBTrainerAI.mediumSkill
      if type && user.pbHasType?(type)
        if user.hasActiveAbility?(:ADAPTABILITY)
          multipliers[:final_damage_multiplier] *= 2
        else
          multipliers[:final_damage_multiplier] *= 1.5
        end
      end
    end
    # Type effectiveness
    if skill>=PBTrainerAI.mediumSkill
      typemod = pbCalcTypeMod(type,user,target)
      multipliers[:final_damage_multiplier] *= typemod.to_f / Effectiveness::NORMAL_EFFECTIVE
    end
    # Burn
    if skill>=PBTrainerAI.highSkill
      if user.status == :BURN && move.physicalMove?(type) &&
         !user.hasActiveAbility?(:GUTS) &&
         !(Settings::MECHANICS_GENERATION >= 6 && move.function == "07E")   # Facade
        multipliers[:final_damage_multiplier] /= 2
      end
    end
    # KIF: Frostbite / Drowsy damage cut (F-BATTLE-06)
    multipliers[:final_damage_multiplier] *= kif_ai_status_damage_mult(move,user,type)
    # Aurora Veil, Reflect, Light Screen
    if skill>=PBTrainerAI.highSkill
      if !move.ignoresReflect? && !user.hasActiveAbility?(:INFILTRATOR)
        if target.pbOwnSide.effects[PBEffects::AuroraVeil] > 0
          if @battle.pbSideBattlerCount(target) > 1
            multipliers[:final_damage_multiplier] *= 2 / 3.0
          else
            multipliers[:final_damage_multiplier] /= 2
          end
        elsif target.pbOwnSide.effects[PBEffects::Reflect] > 0 && move.physicalMove?(type)
          if @battle.pbSideBattlerCount(target) > 1
            multipliers[:final_damage_multiplier] *= 2 / 3.0
          else
            multipliers[:final_damage_multiplier] /= 2
          end
        elsif target.pbOwnSide.effects[PBEffects::LightScreen] > 0 && move.specialMove?(type)
          if @battle.pbSideBattlerCount(target) > 1
            multipliers[:final_damage_multiplier] *= 2 / 3.0
          else
            multipliers[:final_damage_multiplier] /= 2
          end
        end
      end
    end
    # Minimize
    if skill>=PBTrainerAI.highSkill
      if target.effects[PBEffects::Minimize] && move.tramplesMinimize?(2)
        multipliers[:final_damage_multiplier] *= 2
      end
    end
    # Move-specific base damage modifiers
    # TODO
    # Move-specific final damage modifiers
    # TODO
    ##### Main damage calculation #####
    baseDmg = [(baseDmg * multipliers[:base_damage_multiplier]).round, 1].max
    atk     = [(atk     * multipliers[:attack_multiplier]).round, 1].max
    defense = [(defense * multipliers[:defense_multiplier]).round, 1].max
    damage  = (((2.0 * user.level / 5 + 2).floor * baseDmg * atk / defense).floor / 50).floor + 2
    damage  = [(damage  * multipliers[:final_damage_multiplier]).round, 1].max
    # "AI-specific calculations below"
    # Increased critical hit rates
    if skill>=PBTrainerAI.mediumSkill
      c = 0
      # Ability effects that alter critical hit rate
      if c>=0 && user.abilityActive?
        c = BattleHandlers.triggerCriticalCalcUserAbility(user.ability,user,target,c)
      end
      if skill>=PBTrainerAI.bestSkill
        if c>=0 && !moldBreaker && target.abilityActive?
          c = BattleHandlers.triggerCriticalCalcTargetAbility(target.ability,user,target,c)
        end
      end
      # Item effects that alter critical hit rate
      if c>=0 && user.itemActive?
        c = BattleHandlers.triggerCriticalCalcUserItem(user.item,user,target,c)
      end
      if skill>=PBTrainerAI.bestSkill
        if c>=0 && target.itemActive?
          c = BattleHandlers.triggerCriticalCalcTargetItem(target.item,user,target,c)
        end
      end
      # Other efffects
      c = -1 if target.pbOwnSide.effects[PBEffects::LuckyChant]>0
      if c>=0
        c += 1 if move.highCriticalRate?
        c += user.effects[PBEffects::FocusEnergy]
        c += 1 if user.inHyperMode? && move.type == :SHADOW
      end
      if c>=0
        c = 4 if c>4
        damage += damage*0.1*c
      end
    end
    return damage.floor
  end
end
