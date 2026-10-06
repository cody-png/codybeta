#===============================================================================
# F-BATTLE-09 – Exp & EV/IV modes
# Source: KIF 0.20.7
#   011_Battle/003_Battle/004_Battle_ExpAndMoveLearning.rb:62-66,124-163
#   014_Pokemon/001_Pokemon.rb:961 (No-EVs), :2130 (Max IVs)
#
#   ExpAll Redistribution (expall_redist, 0-10, per-save, default 0): KIF's
#                          split of one Exp All share by level gap (see below)
#   Trainer Exp. Boost     (trainerexpboost, 0-1000 step 50, default 50 = PIF's x1.5)
#   EVs Train Mode         (evstrain): defeated foes yield 0 EVs; held Power
#                          items still add their +4 (they modify the yield hash
#                          afterwards, in BattleHandlers::EVGainModifierItem).
#   No-EVs Mode            (noevsmode): EVs are ignored when stats are
#                          calculated (not deleted).
#   Max IVs Mode           (maxivsmode): every IV counts as 31 for stats (not
#                          changed). Like KIF this applies to every Pokémon,
#                          including foes.
#===============================================================================
KIF::Options.define(:expall_redist, 0, :save)
KIF::Options.define(:trainerexpboost, 50, :save)
KIF::Options.define(:evstrain, 0, :save)
KIF::Options.define(:noevsmode, 0, :save)
KIF::Options.define(:maxivsmode, 0, :save)

KIF::Options.add(:battles, :save) {
  SliderOption.new(_INTL("ExpAll Redistribution"), 0, 10, 1,
                   proc { $PokemonSystem.expall_redist },
                   proc { |value| $PokemonSystem.expall_redist = value },
                   _INTL("0 = Off, 10 = Max | Redistributes total exp from expAll to lower level pokemon"))
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("No-EVs Mode"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.noevsmode },
                 proc { |value| $PokemonSystem.noevsmode = value },
                 [_INTL("Pokemon EVs exist."), _INTL("Pokemon EVs are disabled.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Max IVs Mode"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.maxivsmode },
                 proc { |value| $PokemonSystem.maxivsmode = value },
                 [_INTL("Disabled."), _INTL("Pokemon IVs are always at max.")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("EVs Train Mode"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.evstrain },
                 proc { |value| $PokemonSystem.evstrain = value },
                 [_INTL("EVs yielding works as expected."),
                  _INTL("Enemies do not yield EVs (except yielding from held Power-items).")])
}
KIF::Options.add(:battles, :save) {
  SliderOption.new(_INTL("Trainer Exp. Boost"), 0, 1000, 50,
                   proc { $PokemonSystem.trainerexpboost },
                   proc { |value| $PokemonSystem.trainerexpboost = value },
                   _INTL("+x% | Boosts exp. gained in trainer battles (Default: +50%)"))
}

#-------------------------------------------------------------------------------
# Max IVs / No-EVs (stat calculation only)
#-------------------------------------------------------------------------------
class Pokemon
  alias kif_calcIV calcIV unless method_defined?(:kif_calcIV)

  def calcIV
    ret = kif_calcIV
    if $PokemonSystem && $PokemonSystem.maxivsmode > 0
      ret.each_key { |k| ret[k] = IV_STAT_LIMIT }
    end
    return ret
  end

  # Zero EVs for every stat (No-EVs mode); a Hash default so any stat id reads 0
  module ::KIF; module ExpEvIv; ZERO_EV = Hash.new(0).freeze; end; end

  alias kif_calc_stats calc_stats unless method_defined?(:kif_calc_stats)

  def calc_stats(*args)
    return kif_calc_stats(*args) unless $PokemonSystem && $PokemonSystem.noevsmode > 0
    real_ev = @ev
    @ev = KIF::ExpEvIv::ZERO_EV   # read-only during calc_stats (no per-call hash)
    begin
      return kif_calc_stats(*args)
    ensure
      @ev = real_ev
    end
  end

  # EVs Train Mode: species EV yield reads as 0 while EVs are being awarded.
  alias kif_evYield evYield unless method_defined?(:kif_evYield)

  def evYield
    ret = kif_evYield
    ret.each_key { |k| ret[k] = 0 } if KIF.zero_ev_yield?
    return ret
  end
end

module KIF
  @zero_ev_yield = false
  def self.zero_ev_yield?; @zero_ev_yield; end

  def self.with_zero_ev_yield
    old = @zero_ev_yield
    @zero_ev_yield = true
    yield
  ensure
    @zero_ev_yield = old
  end
end

#-------------------------------------------------------------------------------
# Battle side
#-------------------------------------------------------------------------------
KIF.guard_base("011_Battle/003_Battle/004_Battle_ExpAndMoveLearning.rb", 2759027305,
               "PokeBattle_Battle#pbGainExpOne")

class PokeBattle_Battle
  alias kif_pbGainEVsOne pbGainEVsOne unless method_defined?(:kif_pbGainEVsOne)

  def pbGainEVsOne(idxParty, defeatedBattler)
    if $PokemonSystem.evstrain > 0
      KIF.with_zero_ev_yield { kif_pbGainEVsOne(idxParty, defeatedBattler) }
    else
      kif_pbGainEVsOne(idxParty, defeatedBattler)
    end
  end

  # (100 + boost) / 100. KIF default 50 -> x1.5, identical to PIF.
  def kif_trainer_exp_multiplier
    boost = $PokemonSystem.trainerexpboost
    return 1.5 if boost.nil?
    return (100 + boost) / 100.0
  end

  # Exp gained by a non-participant through Exp All (only reached when Exp All
  # is active: the EXPALL item, or Easy difficulty in Kanto – unchanged PIF
  # rule). KIF 0.20.7 (Trapstarr) 004_Battle_ExpAndMoveLearning.rb:129-153,
  # with one fix (Cody, 2026-10-05: "KIF, fixed"):
  #   r = slider 1..10 (0 = Off: everyone gets PIF's a/2)
  #   e = 1 + 0.05 + r^1.1 / 1000           (the slider only bends the curve)
  #   gap_i = highest party level - level_i
  #   exp_i = (a/2) * gap_i^e / sum(gap^e)  (one Exp All share is split)
  # KIF summed the gaps of the whole party (fighters, Exp Share holders, eggs
  # and fainted Pokémon too), so their part of the share was lost; here only
  # the Pokémon receiving Exp All exp this KO are in the sum.
  # The highest-level Pokémon gets nothing from the share. If nobody receiving
  # it is below the highest level, everyone gets a/2 (as KIF's "all the same
  # level" case).
  def kif_expall_share(a, pkmn, idxParty, defeatedBattler, expShare)
    r = $PokemonSystem.expall_redist
    base = a / 2
    return base if r.nil? || r <= 0
    party = pbParty(0)
    recipients = []
    party.each_with_index do |p, i|
      next if !p || p.egg? || !p.able?
      next if defeatedBattler.participants.include?(i) || expShare.include?(i)
      recipients << p
    end
    return base if recipients.empty? || !recipients.any? { |p| p.equal?(pkmn) }
    highest_level = party.select { |p| p && !p.egg? }.map(&:level).max || pkmn.level
    emphasis = 1 + (0.05 + r ** 1.1 / 1000.0)
    weights = recipients.map { |p| [highest_level - p.level, 0].max ** emphasis }
    sum = weights.sum
    return base if sum <= 0
    mine = weights[recipients.index { |p| p.equal?(pkmn) }]
    return (base * mine / sum).round
  end

  #-----------------------------------------------------------------------------
  # Full copy of PIF 6.8.2 PokeBattle_Battle#pbGainExpOne
  # (011_Battle/003_Battle/004_Battle_ExpAndMoveLearning.rb) with the two KIF
  # changes marked "KIF" (ExpAll redistribution, Trainer Exp. Boost, and the
  # F-BATTLE-08 level cap hooks kif_level_cap_active? / kif_apply_level_cap).
  #-----------------------------------------------------------------------------
  def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
    pkmn = pbParty(0)[idxParty] # The Pokémon gaining EVs from defeatedBattler
    growth_rate = pkmn.growth_rate
    # Don't bother calculating if gainer is already at max Exp
    if pkmn.exp >= growth_rate.maximum_exp
      pkmn.calc_stats # To ensure new EVs still have an effect
      return
    end
    isPartic = defeatedBattler.participants.include?(idxParty)
    hasExpShare = expShare.include?(idxParty)
    level = defeatedBattler.level
    # Main Exp calculation
    exp = 0
    a = level * defeatedBattler.pokemon.base_exp
    if expShare.length > 0 && (isPartic || hasExpShare)
      if numPartic == 0 # No participants, all Exp goes to Exp Share holders
        exp = a / (Settings::SPLIT_EXP_BETWEEN_GAINERS ? expShare.length : 1)
      elsif Settings::SPLIT_EXP_BETWEEN_GAINERS # Gain from participating and/or Exp Share
        exp = a / (2 * numPartic) if isPartic
        exp += a / (2 * expShare.length) if hasExpShare
      else
        # Gain from participating and/or Exp Share (Exp not split)
        exp = (isPartic) ? a : a / 2
      end
    elsif isPartic # Participated in battle, no Exp Shares held by anyone
      exp = a / (Settings::SPLIT_EXP_BETWEEN_GAINERS ? numPartic : 1)
    elsif expAll # Didn't participate in battle, gaining Exp due to Exp All
      # NOTE: Exp All works like the Exp Share from Gen 6+, not like the Exp All
      #       from Gen 1, i.e. Exp isn't split between all Pokémon gaining it.
      # KIF (Trapstarr's ExpAll redistribution)
      exp = kif_expall_share(a, pkmn, idxParty, defeatedBattler, expShare)
    end
    return if exp <= 0
    # Pokémon gain more Exp from trainer battles
    # KIF: Trainer Exp. Boost (PIF fixed this at +50%)
    exp = (exp * kif_trainer_exp_multiplier).floor if trainerBattle?
    # Scale the gained Exp based on the gainer's level (or not)
    if Settings::SCALED_EXP_FORMULA
      exp /= 5
      levelAdjust = (2 * level + 10.0) / (pkmn.level + level + 10.0)
      levelAdjust = levelAdjust ** 5
      levelAdjust = Math.sqrt(levelAdjust)
      exp *= levelAdjust
      exp = exp.floor
      exp += 1 if isPartic || hasExpShare
    else
      exp /= 7
    end
    # Foreign Pokémon gain more Exp
    isOutsider = (pkmn.owner.id != pbPlayer.id ||
      (pkmn.owner.language != 0 && pkmn.owner.language != pbPlayer.language)) ||
      pkmn.isSelfFusion? #also self fusions
    if isOutsider
      if pkmn.owner.language != 0 && pkmn.owner.language != pbPlayer.language
        exp = (exp * 1.7).floor
      else
        exp = (exp * 1.5).floor
      end
    end
    # Modify Exp gain based on pkmn's held item
    i = BattleHandlers.triggerExpGainModifierItem(pkmn.item, pkmn, exp)
    if i < 0
      i = BattleHandlers.triggerExpGainModifierItem(@initialItems[0][idxParty], pkmn, exp)
    end
    exp = i if i >= 0
    # Make sure Exp doesn't exceed the maximum
    kif_capped = respond_to?(:kif_level_cap_active?) && kif_level_cap_active?(pkmn)   # KIF
    kif_candies = 0                                                                  # KIF
    if kif_capped                                                                    # KIF
      exp, kif_candies = kif_apply_level_cap(pkmn, exp, growth_rate)                 # KIF
    else                                                                             # KIF
    if pokemonExceedsLevelCap(pkmn)
      if $PokemonSystem.level_caps==1 #Level caps enabled
        exp = 0
      else
        exp = (exp *= 0.6).floor  #Pokémon still gain less exp when over level cap, even if level caps option is disabled
      end
    end


    exp = 0 if $PokemonSystem.level_caps==1 && pokemonExceedsLevelCap(pkmn)
    end                                                                              # KIF

    expFinal = growth_rate.add_exp(pkmn.exp, exp)
    expGained = expFinal - pkmn.exp




    if expGained <= 0
      kif_give_cap_candies(pkmn, kif_candies) if kif_candies > 0                     # KIF
      return
    end
    # "Exp gained" message
    if showMessages
      if isOutsider
        pbDisplayPaused(_INTL("{1} got a boosted {2} Exp. Points!", pkmn.name, expGained))
      else
        pbDisplayPaused(_INTL("{1} got {2} Exp. Points!", pkmn.name, expGained))
      end
    end
    curLevel = pkmn.level
    newLevel = growth_rate.level_from_exp(expFinal)
    dontAnimate=false
    if newLevel < curLevel
      dontAnimate = true
      # debugInfo = "Levels: #{curLevel}->#{newLevel} | Exp: #{pkmn.exp}->#{expFinal} | gain: #{expGained}"
      # raise RuntimeError.new(
      #   echoln  "{1}'s new level is less than its\r\ncurrent level, which shouldn't happen.\r\n[Debug: {2}]",
      #         pkmn.name, debugInfo)
      pbDisplayPaused(_INTL("{1}'s growth rate has changed to '{2}''. Its level will be adjusted to reflect its current exp.", pkmn.name, pkmn.growth_rate.real_name))
    end
    # Give Exp
    if pkmn.shadowPokemon?
      pkmn.exp += expGained
      return
    end
    tempExp1 = pkmn.exp
    battler = pbFindBattler(idxParty)
    loop do
      # For each level gained in turn...
      # EXP Bar animation
      levelMinExp = growth_rate.minimum_exp_for_level(curLevel)
      levelMaxExp = growth_rate.minimum_exp_for_level(curLevel + 1)
      tempExp2 = (levelMaxExp < expFinal) ? levelMaxExp : expFinal
      pkmn.exp = tempExp2



      if pkmn.isFusion?
        if pkmn.exp_gained_since_fused == nil
          pkmn.exp_gained_since_fused = expGained
        else
          pkmn.exp_gained_since_fused += expGained
        end
      end
      pkmn.exp_gained_with_player =0 if pkmn.exp_gained_with_player == nil
      pkmn.exp_gained_with_player += expGained
      @scene.pbEXPBar(battler, levelMinExp, levelMaxExp, tempExp1, tempExp2) if !dontAnimate


      tempExp1 = tempExp2
      curLevel += 1
      if curLevel > newLevel
        # Gained all the Exp now, end the animation
        pkmn.calc_stats
        battler.pbUpdate(false) if battler
        @scene.pbRefreshOne(battler.index) if battler
        break
      end
      # Levelled up
      pbCommonAnimation("LevelUp", battler) if battler
      oldTotalHP = pkmn.totalhp
      oldAttack = pkmn.attack
      oldDefense = pkmn.defense
      oldSpAtk = pkmn.spatk
      oldSpDef = pkmn.spdef
      oldSpeed = pkmn.speed
      if battler && battler.pokemon
        battler.pokemon.changeHappiness("levelup")
      end
      pkmn.calc_stats
      battler.pbUpdate(false) if battler
      @scene.pbRefreshOne(battler.index) if battler
      pbDisplayPaused(_INTL("{1} grew to Lv. {2}!", pkmn.name, curLevel))
      if !$game_switches[SWITCH_NO_LEVELS_MODE]
        @scene.pbLevelUp(pkmn, battler, oldTotalHP, oldAttack, oldDefense,
                         oldSpAtk, oldSpDef, oldSpeed)
      end
      # Learn all moves learned at this level
      moveList = pkmn.getMoveList
      moveList.each { |m| pbLearnMove(idxParty, m[1]) if m[0] == curLevel }
    end
    kif_give_cap_candies(pkmn, kif_candies) if kif_candies > 0                       # KIF
  end
end
