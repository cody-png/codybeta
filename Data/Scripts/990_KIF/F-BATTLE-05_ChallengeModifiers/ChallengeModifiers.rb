#===============================================================================
# F-BATTLE-05 – Challenge modifiers: Metronome Madness, Letdown, Berserker
# Source: KIF 0.20.7
#   011_Battle/001_Battler/007_Battler_UseMove.rb:186-244 (Letdown/Metronome)
#   011_Battle/003_Battle/012_Battle_Phase_EndOfRound.rb:221-240 (Berserker)
#
#   Metronome Madness (ch_metronome): Off / Normal (every Pokémon's move
#     becomes Metronome) / Hard (only the player's Pokémon).
#   Letdown (ch_letdown): Off/1%/5%/10%/25%/50% chance the move becomes
#     Splash. "Letdown Player Only" (ch_letdownplayer) limits it to the player.
#   Berserker (ch_berserker): at end of round, after weather, every
#     non-player battler gets +1 Atk/Def/SpA/SpD/Spe every 3 turns (Easy),
#     2 turns (Normal) or every turn (Hard/Chaos).
#
# KIF quirks kept as-is (see port notes):
#   * The replaced move bypasses pbTryUseMove, so a sleeping, frozen or fully
#     paralysed Pokémon still uses Metronome/Splash, and no PP is used.
#   * "Chaos" is described as +2 per turn, but KIF's code gives +1 per turn,
#     i.e. the same as Hard.
#   * Berserker boosts partner-trainer Pokémon on the player's side too
#     (only the player's own are skipped).
#===============================================================================
KIF::Options.define(:ch_metronome, 0, :save)
KIF::Options.define(:ch_letdown, 0, :save)
KIF::Options.define(:ch_letdownplayer, 0, :save)
KIF::Options.define(:ch_berserker, 0, :save)

KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Metronome Madness"), [_INTL("Off"), _INTL("Normal"), _INTL("Hard")],
                 proc { $PokemonSystem.ch_metronome },
                 proc { |value| $PokemonSystem.ch_metronome = value },
                 [_INTL("Metronome disabled."),
                  _INTL("All Pokemons are forced to use Metronome. [Normal]"),
                  _INTL("Only your Pokemons are forced to use Metronome. [Hard]")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Letdown"), [_INTL("Off"), _INTL("1%"), _INTL("5%"), _INTL("10%"), _INTL("25%"), _INTL("50%")],
                 proc { $PokemonSystem.ch_letdown },
                 proc { |value| $PokemonSystem.ch_letdown = value },
                 [_INTL("Letdown disabled."),
                  _INTL("1% chance that Pokemons use Splash instead."),
                  _INTL("5% chance that Pokemons use Splash instead."),
                  _INTL("10% chance that Pokemons use Splash instead."),
                  _INTL("25% chance that Pokemons use Splash instead."),
                  _INTL("50% chance that Pokemons use Splash instead.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Letdown Player Only"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.ch_letdownplayer },
                 proc { |value| $PokemonSystem.ch_letdownplayer = value },
                 [_INTL("Letdown doesn't only affect the player."),
                  _INTL("Letdown only affects the player.")])
}
KIF::Options.add(:challenges, :save) {
  EnumOption.new(_INTL("Berserker"), [_INTL("Off"), _INTL("Easy"), _INTL("Normal"), _INTL("Hard"), _INTL("Chaos")],
                 proc { $PokemonSystem.ch_berserker },
                 proc { |value| $PokemonSystem.ch_berserker = value },
                 [_INTL("Berserker disabled."),
                  _INTL("Opponent stats raise by 1 every 3 turns. [Easy]"),
                  _INTL("Opponent stats raise by 1 every 2 turns. [Normal]"),
                  _INTL("Opponent stats raise by 1 every turn. [Hard]"),
                  _INTL("Opponent stats raise by 2 every turn. [Hardcore]")])
}

#-------------------------------------------------------------------------------
# Berserker – runs right after pbEORWeather, exactly where KIF inserted it in
# pbEndOfRoundPhase (pbEORWeather is only called from there).
#-------------------------------------------------------------------------------
class PokeBattle_Battle
  alias kif_pbEORWeather pbEORWeather unless method_defined?(:kif_pbEORWeather)

  def pbEORWeather(priority)
    kif_pbEORWeather(priority)
    kif_berserker_increase
  end

  def kif_berserker_increase
    mode = $PokemonSystem.ch_berserker
    return if mode.nil? || mode == 0
    requiredturns = [1, 3, 2, 1, 1]
    @positions.each_with_index do |pos, idxPos|
      battler = @battlers[idxPos]
      next if !pos || !battler || battler.pbOwnedByPlayerSerious?
      if requiredturns[mode] > 1
        next if battler.turnCount % requiredturns[mode] != 0
      end
      berserkup = [:ATTACK, 1, :DEFENSE, 1, :SPECIAL_ATTACK, 1, :SPECIAL_DEFENSE, 1, :SPEED, 1]
      next if !battler.pbCanRaiseStatStage?(berserkup[0], battler, self, true)
      pbDisplay(_INTL("All stats from {1} increased! [BERSERKER MODE]", battler.pbThis))
      showAnim = true
      for i in 0...berserkup.length / 2
        next if !battler.pbCanRaiseStatStage?(berserkup[i * 2], battler, self)
        if battler.pbRaiseStatStage(berserkup[i * 2], berserkup[i * 2 + 1], battler, showAnim)
          showAnim = false
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Letdown / Metronome Madness – full copy of PIF 6.8.2
# PokeBattle_Battler#pbUseMove (011_Battle/001_Battler/007_Battler_UseMove.rb)
# with the KIF block inserted before the "Labels the move" step.
#-------------------------------------------------------------------------------
KIF.guard_base("011_Battle/001_Battler/007_Battler_UseMove.rb", 3893353249,
               "PokeBattle_Battler#pbUseMove")

class PokeBattle_Battler
  def pbUseMove(choice, specialUsage = false)
    # NOTE: This is intentionally determined before a multi-turn attack can
    #       set specialUsage to true.
    skipAccuracyCheck = (specialUsage && choice[2] != @battle.struggle)
    # Start using the move
    pbBeginTurn(choice)
    # Force the use of certain moves if they're already being used
    if usingMultiTurnAttack?
      choice[2] = PokeBattle_Move.from_pokemon_move(@battle, Pokemon::Move.new(@currentMove))
      specialUsage = true
    elsif @effects[PBEffects::Encore] > 0 && choice[1] >= 0 &&
      @battle.pbCanShowCommands?(@index)
      idxEncoredMove = pbEncoredMoveIndex
      if idxEncoredMove >= 0 && @battle.pbCanChooseMove?(@index, idxEncoredMove, false)
        if choice[1] != idxEncoredMove # Change move if battler was Encored mid-round
          choice[1] = idxEncoredMove
          choice[2] = @moves[idxEncoredMove]
          choice[3] = -1 # No target chosen
        end
      end
    end
    # KIF – Challenge modifiers (Letdown / Metronome Madness). When one
    # triggers, the replacement move skips pbTryUseMove and PP use (KIF
    # 007_Battler_UseMove.rb:186-244).
    normallogic = true
    isletdown = false
    if $PokemonSystem.ch_letdown != 0 && !specialUsage
      skipletdown = $PokemonSystem.ch_letdownplayer == 1 && !pbOwnedByPlayerSerious?
      if !skipletdown
        letdownrng = rand(1..100)
        letdownprob = [0, 1, 5, 10, 25, 50, 50]
        if letdownprob[$PokemonSystem.ch_letdown] >= letdownrng
          isletdown = true
          normallogic = false
          move = PokeBattle_Move.from_pokemon_move(@battle, Pokemon::Move.new(:SPLASH))
        end
      end
    end
    if !usingMultiTurnAttack? && !specialUsage && !isletdown
      if $PokemonSystem.ch_metronome == 1 || ($PokemonSystem.ch_metronome == 2 && pbOwnedByPlayerSerious?)
        move = PokeBattle_Move.from_pokemon_move(@battle, Pokemon::Move.new(:METRONOME))
        normallogic = false
      end
    end
    if normallogic
    # Labels the move being used as "move"
    move = choice[2]
    return if !move # if move was not chosen somehow
    # Try to use the move (inc. disobedience)
    @lastMoveFailed = false
    if !pbTryUseMove(choice, move, specialUsage, skipAccuracyCheck)
      @lastMoveUsed = nil
      @lastMoveUsedType = nil
      if !specialUsage
        @lastRegularMoveUsed = nil
        @lastRegularMoveTarget = -1
      end
      @battle.pbGainExp # In case self is KO'd due to confusion
      pbCancelMoves
      pbEndTurn(choice)
      return
    end
    move = choice[2] # In case disobedience changed the move to be used
    return if !move # if move was not chosen somehow
    # Subtract PP
    if !specialUsage
      if !pbReducePP(move)
        @battle.pbDisplay(_INTL("{1} used {2}!", pbThis, move.name))
        @battle.pbDisplay(_INTL("But there was no PP left for the move!"))
        @lastMoveUsed = nil
        @lastMoveUsedType = nil
        @lastRegularMoveUsed = nil
        @lastRegularMoveTarget = -1
        @lastMoveFailed = true
        pbCancelMoves
        pbEndTurn(choice)
        return
      end
    end
    end # KIF normallogic
    # Stance Change
    if self.ability == :STANCECHANGE
      if move.damagingMove?
        user = pbFindUser(choice, move)
        stanceChangeEffect(user, true)
      elsif move.id == :KINGSSHIELD
        user = pbFindUser(choice, move)
        stanceChangeEffect(user, false)
      end
    end
    # Calculate the move's type during this usage
    move.calcType = move.pbCalcType(self)
    # Start effect of Mold Breaker
    @battle.moldBreaker = hasMoldBreaker?
    # Remember that user chose a two-turn move
    if move.pbIsChargingTurn?(self)
      # Beginning the use of a two-turn attack
      @effects[PBEffects::TwoTurnAttack] = move.id
      @currentMove = move.id
    else
      @effects[PBEffects::TwoTurnAttack] = nil # Cancel use of two-turn attack
    end
    # Add to counters for moves which increase them when used in succession
    move.pbChangeUsageCounters(self, specialUsage)
    # Charge up Metronome item
    if hasActiveItem?(:METRONOME) && !move.callsAnotherMove?
      if @lastMoveUsed && @lastMoveUsed == move.id && !@lastMoveFailed
        @effects[PBEffects::Metronome] += 1
      else
        @effects[PBEffects::Metronome] = 0
      end
    end
    # Record move as having been used
    @lastMoveUsed = move.id
    @lastMoveUsedType = move.calcType # For Conversion 2
    if !specialUsage
      @lastRegularMoveUsed = move.id # For Disable, Encore, Instruct, Mimic, Mirror Move, Sketch, Spite
      @lastRegularMoveTarget = choice[3] # For Instruct (remembering original target is fine)
      @movesUsed.push(move.id) if !@movesUsed.include?(move.id) # For Last Resort
    end
    @battle.lastMoveUsed = move.id # For Copycat
    @battle.lastMoveUser = @index # For "self KO" battle clause to avoid draws
    @battle.successStates[@index].useState = 1 # Battle Arena - assume failure
    # Find the default user (self or Snatcher) and target(s)
    user = pbFindUser(choice, move)
    user = pbChangeUser(choice, move, user)
    targets = pbFindTargets(choice, move, user)
    targets = pbChangeTargets(move, user, targets)
    # Pressure
    if !specialUsage
      targets.each do |b|
        next unless b.opposes?(user) && b.hasActiveAbility?(:PRESSURE)
        PBDebug.log("[Ability triggered] #{b.pbThis}'s #{b.abilityName}")
        user.pbReducePP(move)
      end
      if move.pbTarget(user).affects_foe_side
        @battle.eachOtherSideBattler(user) do |b|
          next unless b.hasActiveAbility?(:PRESSURE)
          PBDebug.log("[Ability triggered] #{b.pbThis}'s #{b.abilityName}")
          user.pbReducePP(move)
        end
      end
    end
    # Dazzling/Queenly Majesty make the move fail here
    @battle.pbPriority(true).each do |b|
      next if !b || !b.abilityActive?
      if BattleHandlers.triggerMoveBlockingAbility(b.ability, b, user, targets, move, @battle)
        @battle.pbDisplayBrief(_INTL("{1} used {2}!", user.pbThis, move.name))
        @battle.pbShowAbilitySplash(b)
        @battle.pbDisplay(_INTL("{1} cannot use {2}!", user.pbThis, move.name))
        @battle.pbHideAbilitySplash(b)
        user.lastMoveFailed = true
        pbCancelMoves
        pbEndTurn(choice)
        return
      end
    end
    # "X used Y!" message
    # Can be different for Bide, Fling, Focus Punch and Future Sight
    # NOTE: This intentionally passes self rather than user. The user is always
    #       self except if Snatched, but this message should state the original
    #       user (self) even if the move is Snatched.
    move.pbDisplayUseMessage(self)
    # Snatch's message (user is the new user, self is the original user)
    if move.snatched
      @lastMoveFailed = true # Intentionally applies to self, not user
      @battle.pbDisplay(_INTL("{1} snatched {2}'s move!", user.pbThis, pbThis(true)))
    end
    # "But it failed!" checks
    if move.pbMoveFailed?(user, targets)
      PBDebug.log(sprintf("[Move failed] In function code %s's def pbMoveFailed?", move.function))
      user.lastMoveFailed = true
      pbCancelMoves
      pbEndTurn(choice)
      return
    end
    # Perform set-up actions and display messages
    # Messages include Magnitude's number and Pledge moves' "it's a combo!"
    move.pbOnStartUse(user, targets)
    # Self-thawing due to the move
    if user.status == :FROZEN && move.thawsUser?
      user.pbCureStatus(false)
      @battle.pbDisplay(_INTL("{1} melted the ice!", user.pbThis))
    end
    # Powder
    if user.effects[PBEffects::Powder] && move.calcType == :FIRE
      @battle.pbCommonAnimation("Powder", user)
      @battle.pbDisplay(_INTL("When the flame touched the powder on the Pokémon, it exploded!"))
      user.lastMoveFailed = true
      if ![:Rain, :HeavyRain].include?(@battle.pbWeather) && user.takesIndirectDamage?
        oldHP = user.hp
        user.pbReduceHP((user.totalhp / 4.0).round, false)
        user.pbFaint if user.fainted?
        @battle.pbGainExp # In case user is KO'd by this
        user.pbItemHPHealCheck
        if user.pbAbilitiesOnDamageTaken(oldHP)
          user.pbEffectsOnSwitchIn(true)
        end
      end
      pbCancelMoves
      pbEndTurn(choice)
      return
    end
    # Primordial Sea, Desolate Land
    if move.damagingMove?
      case @battle.pbWeather
      when :HeavyRain
        if move.calcType == :FIRE
          @battle.pbDisplay(_INTL("The Fire-type attack fizzled out in the heavy rain!"))
          user.lastMoveFailed = true
          pbCancelMoves
          pbEndTurn(choice)
          return
        end
      when :HarshSun
        if move.calcType == :WATER
          @battle.pbDisplay(_INTL("The Water-type attack evaporated in the harsh sunlight!"))
          user.lastMoveFailed = true
          pbCancelMoves
          pbEndTurn(choice)
          return
        end
      end
    end
    # Protean
    if user.hasActiveAbility?(:PROTEAN) && !move.callsAnotherMove? && !move.snatched
      if user.pbHasOtherType?(move.calcType) && !GameData::Type.get(move.calcType).pseudo_type
        @battle.pbShowAbilitySplash(user)
        user.pbChangeTypes(move.calcType)
        typeName = GameData::Type.get(move.calcType).name
        @battle.pbDisplay(_INTL("{1} transformed into the {2} type!", user.pbThis, typeName))
        @battle.pbHideAbilitySplash(user)
        # NOTE: The GF games say that if Curse is used by a non-Ghost-type
        #       Pokémon which becomes Ghost-type because of Protean, it should
        #       target and curse itself. I think this is silly, so I'm making it
        #       choose a random opponent to curse instead.
        if move.function == "10D" && targets.length == 0 # Curse
          choice[3] = -1
          targets = pbFindTargets(choice, move, user)
        end
      end
    end
    #---------------------------------------------------------------------------
    magicCoater = -1
    magicBouncer = -1
    if targets.length == 0 && move.pbTarget(user).num_targets > 0 && !move.worksWithNoTargets?
      # def pbFindTargets should have found a target(s), but it didn't because
      # they were all fainted
      # All target types except: None, User, UserSide, FoeSide, BothSides
      @battle.pbDisplay(_INTL("But there was no target..."))
      user.lastMoveFailed = true
    else
      # We have targets, or move doesn't use targets
      # Reset whole damage state, perform various success checks (not accuracy)
      user.initialHP = user.hp
      targets.each do |b|
        b.damageState.reset
        b.damageState.initialHP = b.hp
        if !pbSuccessCheckAgainstTarget(move, user, b)
          b.damageState.unaffected = true
        end
      end
      # Magic Coat/Magic Bounce checks (for moves which don't target Pokémon)
      if targets.length == 0 && move.canMagicCoat?
        @battle.pbPriority(true).each do |b|
          next if b.fainted? || !b.opposes?(user)
          next if b.semiInvulnerable?
          if b.effects[PBEffects::MagicCoat]
            magicCoater = b.index
            b.effects[PBEffects::MagicCoat] = false
            break
          elsif b.hasActiveAbility?(:MAGICBOUNCE) && !@battle.moldBreaker &&
            !b.effects[PBEffects::MagicBounce]
            magicBouncer = b.index
            b.effects[PBEffects::MagicBounce] = true
            break
          end
        end
      end
      # Get the number of hits
      numHits = move.pbNumHits(user, targets)
      # Process each hit in turn
      realNumHits = 0
      for i in 0...numHits
        break if magicCoater >= 0 || magicBouncer >= 0
        success = pbProcessMoveHit(move, user, targets, i, skipAccuracyCheck)
        if !success
          if i == 0 && targets.length > 0
            hasFailed = false
            targets.each do |t|
              next if t.damageState.protected
              hasFailed = t.damageState.unaffected
              break if !t.damageState.unaffected
            end
            user.lastMoveFailed = hasFailed
          end
          break
        end
        realNumHits += 1
        break if user.fainted?
        break if [:SLEEP, :FROZEN].include?(user.status)
        # NOTE: If a multi-hit move becomes disabled partway through doing those
        #       hits (e.g. by Cursed Body), the rest of the hits continue as
        #       normal.
        break if !targets.any? { |t| !t.fainted? } # All targets are fainted
      end
      # Battle Arena only - attack is successful
      @battle.successStates[user.index].useState = 2
      if targets.length > 0
        @battle.successStates[user.index].typeMod = 0
        targets.each do |b|
          next if b.damageState.unaffected
          @battle.successStates[user.index].typeMod += b.damageState.typeMod
        end
      end
      # Effectiveness message for multi-hit moves
      # NOTE: No move is both multi-hit and multi-target, and the messages below
      #       aren't quite right for such a hypothetical move.
      if numHits > 1
        if move.damagingMove?
          targets.each do |b|
            next if b.damageState.unaffected || b.damageState.substitute
            move.pbEffectivenessMessage(user, b, targets.length)
          end
        end
        if realNumHits == 1
          @battle.pbDisplay(_INTL("Hit 1 time!"))
        elsif realNumHits > 1
          @battle.pbDisplay(_INTL("Hit {1} times!", realNumHits))
        end
      end
      # Magic Coat's bouncing back (move has targets)
      targets.each do |b|
        next if b.fainted?
        next if !b.damageState.magicCoat && !b.damageState.magicBounce
        @battle.pbShowAbilitySplash(b) if b.damageState.magicBounce
        @battle.pbDisplay(_INTL("{1} bounced the {2} back!", b.pbThis, move.name))
        @battle.pbHideAbilitySplash(b) if b.damageState.magicBounce
        newChoice = choice.clone
        newChoice[3] = user.index
        newTargets = pbFindTargets(newChoice, move, b)
        newTargets = pbChangeTargets(move, b, newTargets)
        success = pbProcessMoveHit(move, b, newTargets, 0, false)
        b.lastMoveFailed = true if !success
        targets.each { |otherB| otherB.pbFaint if otherB && otherB.fainted? }
        user.pbFaint if user.fainted?
      end
      # Magic Coat's bouncing back (move has no targets)
      if magicCoater >= 0 || magicBouncer >= 0
        mc = @battle.battlers[(magicCoater >= 0) ? magicCoater : magicBouncer]
        if !mc.fainted?
          user.lastMoveFailed = true
          @battle.pbShowAbilitySplash(mc) if magicBouncer >= 0
          @battle.pbDisplay(_INTL("{1} bounced the {2} back!", mc.pbThis, move.name))
          @battle.pbHideAbilitySplash(mc) if magicBouncer >= 0
          success = pbProcessMoveHit(move, mc, [], 0, false)
          mc.lastMoveFailed = true if !success
          targets.each { |b| b.pbFaint if b && b.fainted? }
          user.pbFaint if user.fainted?
        end
      end
      # Move-specific effects after all hits
      targets.each { |b| move.pbEffectAfterAllHits(user, b) }
      # Faint if 0 HP
      targets.each { |b| b.pbFaint if b && b.fainted? }
      user.pbFaint if user.fainted?
      # External/general effects after all hits. Eject Button, Shell Bell, etc.
      pbEffectsAfterMove(user, targets, move, realNumHits)
    end
    # End effect of Mold Breaker
    @battle.moldBreaker = false
    # Gain Exp
    @battle.pbGainExp
    # Battle Arena only - update skills
    @battle.eachBattler { |b| @battle.successStates[b.index].updateSkill }
    # Shadow Pokémon triggering Hyper Mode
    pbHyperMode if @battle.choices[@index][0] != :None # Not if self is replaced
    # End of move usage
    pbEndTurn(choice)
    # Instruct
    @battle.eachBattler do |b|
      next if !b.effects[PBEffects::Instruct] || !b.lastMoveUsed
      b.effects[PBEffects::Instruct] = false
      idxMove = -1
      b.eachMoveWithIndex { |m, i| idxMove = i if m.id == b.lastMoveUsed }
      next if idxMove < 0
      oldLastRoundMoved = b.lastRoundMoved
      @battle.pbDisplay(_INTL("{1} used the move instructed by {2}!", b.pbThis, user.pbThis(true)))
      PBDebug.logonerr {
        b.effects[PBEffects::Instructed] = true
        b.pbUseMoveSimple(b.lastMoveUsed, b.lastRegularMoveTarget, idxMove, false)
        b.effects[PBEffects::Instructed] = false
      }
      b.lastRoundMoved = oldLastRoundMoved
      @battle.pbJudge
      return if @battle.decision > 0
    end
    # Dancer
    if !@effects[PBEffects::Dancer] && !user.lastMoveFailed && realNumHits > 0 &&
      !move.snatched && magicCoater < 0 && @battle.pbCheckGlobalAbility(:DANCER) &&
      move.danceMove?
      dancers = []
      @battle.pbPriority(true).each do |b|
        dancers.push(b) if b.index != user.index && b.hasActiveAbility?(:DANCER)
      end
      while dancers.length > 0
        nextUser = dancers.pop
        oldLastRoundMoved = nextUser.lastRoundMoved
        # NOTE: Petal Dance being used because of Dancer shouldn't lock the
        #       Dancer into using that move, and shouldn't contribute to its
        #       turn counter if it's already locked into Petal Dance.
        oldOutrage = nextUser.effects[PBEffects::Outrage]
        nextUser.effects[PBEffects::Outrage] += 1 if nextUser.effects[PBEffects::Outrage] > 0
        oldCurrentMove = nextUser.currentMove
        preTarget = choice[3]
        preTarget = user.index if nextUser.opposes?(user) || !nextUser.opposes?(preTarget)
        @battle.pbShowAbilitySplash(nextUser, true)
        @battle.pbHideAbilitySplash(nextUser)
        if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          @battle.pbDisplay(_INTL("{1} kept the dance going with {2}!",
                                  nextUser.pbThis, nextUser.abilityName))
        end
        PBDebug.logonerr {
          nextUser.effects[PBEffects::Dancer] = true
          nextUser.pbUseMoveSimple(move.id, preTarget)
          nextUser.effects[PBEffects::Dancer] = false
        }
        nextUser.lastRoundMoved = oldLastRoundMoved
        nextUser.effects[PBEffects::Outrage] = oldOutrage
        nextUser.currentMove = oldCurrentMove
        @battle.pbJudge
        return if @battle.decision > 0
      end
    end
  end
end
