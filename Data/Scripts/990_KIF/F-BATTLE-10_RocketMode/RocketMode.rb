#===============================================================================
# F-BATTLE-10 – Rocket Mode (catch trainers' Pokémon), Reïzod
# Source: KIF 0.20.7
#   011_Battle/003_Battle/001_PokeBattle_BattleCommon.rb:149-159, :208
#   013_Items/003_Item_BattleEffects.rb:57-60
#   016_UI/015_UI_Options.rb:2423-2429 ("Rocket Mode", Battles & Pokemons)
#   016_UI/001_UI_PauseMenu.rb:418 (Rocket Balls in the Kuray Shop)
#
# Off / On (Rocket Balls aren't deflected in trainer battles) / All Balls
# (no ball is). A stolen Pokémon keeps its trainer as OT, like KIF (KIF only
# gave the player ownership for a Snag Ball that wasn't a steal). Never while
# Self-Battle's "no money lost" is on (KIF).
#
# 6.8.2 adaptations: 6.8.2 already lets balls be thrown with several
# opponents out (KIF had to lift that check for steal balls), so only the
# deflection in pbThrowPokeBall changes. Copy of the 6.8.2 method below with
# the KIF lines marked; Rocket Balls are recognised by symbol (:ROCKETBALL),
# not KIF's item number 623.
#===============================================================================
KIF::Options.define(:rocketballsteal, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Rocket Mode"), [_INTL("Off"), _INTL("On"), _INTL("All Balls")],
                 proc { $PokemonSystem.rocketballsteal },
                 proc { |value| $PokemonSystem.rocketballsteal = value },
                 [_INTL("Rocket Balls don't steal Pokemons."),
                  _INTL("Rocket Balls can steal Pokemons."),
                  _INTL("Every Balls can steal Pokemons.")])
}

KIF.guard_base("011_Battle/003_Battle/001_PokeBattle_BattleCommon.rb", 563813507,
               "PokeBattle_BattleCommon#pbThrowPokeBall")

module PokeBattle_BattleCommon
  def kif_rocket_steal_ball?(ball)
    mode = $PokemonSystem ? $PokemonSystem.rocketballsteal.to_i : 0
    return false if mode <= 0 || !trainerBattle?
    return false if $PokemonSystem.respond_to?(:nomoneylost) && $PokemonSystem.nomoneylost.to_i == 1
    return mode > 1 || GameData::Item.get(ball).id == :ROCKETBALL
  end

  # Copy of 6.8.2 pbThrowPokeBall (001_PokeBattle_BattleCommon.rb:114) with
  # the KIF lines marked.
  def pbThrowPokeBall(idxBattler, ball, catch_rate = nil, showPlayer = false)
    # Determine which Pokémon you're throwing the Poké Ball at
    battler = nil
    if opposes?(idxBattler)
      battler = @battlers[idxBattler]
    else
      battler = @battlers[idxBattler].pbDirectOpposing(true)
    end
    if battler.fainted?
      battler.eachAlly do |b|
        battler = b
        break
      end
    end
    # Messages
    itemName = GameData::Item.get(ball).name
    if battler.fainted?
      if itemName.starts_with_vowel?
        pbDisplay(_INTL("{1} threw an {2}!", pbPlayer.name, itemName))
      else
        pbDisplay(_INTL("{1} threw a {2}!", pbPlayer.name, itemName))
      end
      pbDisplay(_INTL("But there was no target..."))
      return
    end
    if itemName.starts_with_vowel?
      pbDisplayBrief(_INTL("{1} threw an {2}!", pbPlayer.name, itemName))
    else
      pbDisplayBrief(_INTL("{1} threw a {2}!", pbPlayer.name, itemName))
    end
    # Animation of opposing trainer blocking Poké Balls (unless it's a Snag Ball
    # at a Shadow Pokémon)
    is_steal_ball = kif_rocket_steal_ball?(ball)                                    # KIF
    if trainerBattle? && !(GameData::Item.get(ball).is_snag_ball? && battler.shadowPokemon?) && !is_steal_ball   # KIF
      @scene.pbThrowAndDeflect(ball, 1)
      pbDisplay(_INTL("The Trainer blocked your Poké Ball! Don't be a thief!"))
      return
    elsif $game_switches[SWITCH_CANNOT_CATCH_POKEMON]
      @scene.pbThrowAndDeflect(ball, 1)
      pbDisplay(_INTL("The Pokémon is impossible to catch!"))
      return
    end
    # Calculate the number of shakes (4=capture)
    pkmn = battler.pokemon
    @criticalCapture = false
    numShakes = pbCaptureCalc(pkmn, battler, catch_rate, ball)
    PBDebug.log("[Threw Poké Ball] #{itemName}, #{numShakes} shakes (4=capture)")
    # Animation of Ball throw, absorb, shake and capture/burst out
    @scene.pbThrow(ball, numShakes, @criticalCapture, battler.index, showPlayer)
    # Outcome message
    case numShakes
    when 0
      pbDisplay(_INTL("Oh no! The Pokémon broke free!"))
      BallHandlers.onFailCatch(ball, self, battler)
    when 1
      pbDisplay(_INTL("Aww! It appeared to be caught!"))
      BallHandlers.onFailCatch(ball, self, battler)
    when 2
      pbDisplay(_INTL("Aargh! Almost had it!"))
      BallHandlers.onFailCatch(ball, self, battler)
    when 3
      pbDisplay(_INTL("Gah! It was so close, too!"))
      BallHandlers.onFailCatch(ball, self, battler)
    when 4
      if $game_switches[SWITCH_SILVERBOSS_BATTLE]
        pkmn.species = :PALDIATINA
        pkmn.name = "Paldiatina"
      end
      pbDisplayBrief(_INTL("Gotcha! {1} was caught!", pkmn.name))
      @scene.pbThrowSuccess # Play capture success jingle
      pbRemoveFromParty(battler.index, battler.pokemonIndex)
      # Gain Exp
      if Settings::GAIN_EXP_FOR_CAPTURE
        battler.captured = true
        pbGainExp
        battler.captured = false
      end
      battler.pbReset
      if pbAllFainted?(battler.index)
        @decision = (trainerBattle?) ? 1 : 4 # Battle ended by win/capture
      end
      # Modify the Pokémon's properties because of the capture
      if GameData::Item.get(ball).is_snag_ball? && !is_steal_ball                    # KIF
        pkmn.owner = Pokemon::Owner.new_from_trainer(pbPlayer)
      end
      BallHandlers.onCatch(ball, self, pkmn)
      checkCatchChallenge(ball, self, pkmn)

      pkmn.poke_ball = ball
      pkmn.makeUnmega if pkmn.mega?
      pkmn.makeUnprimal
      pkmn.update_shadow_moves if pkmn.shadowPokemon?
      pkmn.record_first_moves
      # Reset form
      pkmn.forced_form = nil if MultipleForms.hasFunction?(pkmn.species, "getForm")
      @peer.pbOnLeavingBattle(self, pkmn, true, true)
      # Make the Poké Ball and data box disappear
      @scene.pbHideCaptureBall(idxBattler)
      # Save the Pokémon for storage at the end of battle
      @caughtPokemon.push(pkmn)
    end
  end
end
