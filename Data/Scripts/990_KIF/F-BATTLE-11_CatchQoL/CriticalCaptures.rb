#===============================================================================
# F-BATTLE-11 (part) – Critical Captures option
# Source: KIF 0.20.7 002_BattleSettings.rb:67 (ENABLE_CRITICAL_CAPTURES = true)
#         and 011_Battle/003_Battle/001_PokeBattle_BattleCommon.rb pbCaptureCalc
#
# "Critical Captures" (critical_captures, per-save, default On – Cody's call).
# PIF 6.8.2 removed the Settings-driven check and instead gives a guaranteed
# "last ball" critical capture (x*6/12, or always for shinies) when the thrown
# ball is the last one in the bag. That stays as is; KIF's check runs after it
# when the option is On:
#     Pokémon owned  > 600: c = x*5/12   > 450: x*4/12   > 300: x*3/12   else x*2/12
#     critical if pbRandom(256) < c  -> caught immediately (KIF: no shake roll)
# where x is the modified catch value (1..254) from PIF's formula.
#===============================================================================
KIF::Options.define(:critical_captures, 1, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Critical Captures"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.critical_captures },
                 proc { |value| $PokemonSystem.critical_captures = value },
                 [_INTL("Only PIF's last-ball critical captures."),
                  _INTL("Critical captures can happen with any ball (more likely with more Pokémon owned).")])
}

KIF.guard_base("011_Battle/003_Battle/001_PokeBattle_BattleCommon.rb", 563813507,
               "PokeBattle_BattleCommon#pbCaptureCalc")

module PokeBattle_BattleCommon
  # Full copy of PIF 6.8.2 pbCaptureCalc with the KIF block marked "KIF".
  def pbCaptureCalc(pkmn, battler, catch_rate, ball)
    return 4 if $DEBUG && Input.press?(Input::CTRL)
    # Get a catch rate if one wasn't provided
    catch_rate = pkmn.species_data.catch_rate if !catch_rate
    # Modify catch_rate depending on the Poké Ball's effect
    ultraBeast = [:NIHILEGO, :BUZZWOLE, :PHEROMOSA, :XURKITREE, :CELESTEELA,
                  :KARTANA, :GUZZLORD, :POIPOLE, :NAGANADEL, :STAKATAKA,
                  :BLACEPHALON].include?(pkmn.species)
    if !ultraBeast || ball == :BEASTBALL
      catch_rate = BallHandlers.modifyCatchRate(ball, catch_rate, self, battler, ultraBeast)
    else
      catch_rate /= 10
    end

    if @scene&.battle&.caughtOffGuard
      catch_rate = [catch_rate * 1.5, 255].min
    end

    # First half of the shakes calculation
    a = battler.totalhp
    b = battler.hp
    x = ((3 * a - 2 * b) * catch_rate.to_f) / (3 * a)
    # Calculation modifiers
    if battler.status == :SLEEP || battler.status == :FROZEN
      x *= 2.5
    elsif battler.status != :NONE
      x *= 1.5
    end
    x = x.floor
    x = 1 if x < 1
    # Definite capture, no need to perform randomness checks
    return 4 if x >= 255 || BallHandlers.isUnconditional?(ball, self, battler)
    # Second half of the shakes calculation
    y = (65536 / ((255.0 / x) ** 0.1875)).floor

    #Increased chances of catching if is on last ball
    isOnLastBall = !$PokemonBag.pbHasItem?(ball)
    # Critical capture check
    if isOnLastBall
      c = x * 6 / 12
      if c > 0 && pbRandom(256) < c || pkmn.shiny?
        @criticalCapture = true
        return 4
      end
    end

    # KIF – Critical captures (KIF 001_PokeBattle_BattleCommon.rb, enabled by
    # ENABLE_CRITICAL_CAPTURES = true). Chance c/256 with c = x*2/12 .. x*5/12
    # depending on Pokémon owned; a critical capture always succeeds.
    if $PokemonSystem.critical_captures == 1
      c = 0
      numOwned = $Trainer.pokedex.owned_count
      if numOwned > 600
        c = x * 5 / 12
      elsif numOwned > 450
        c = x * 4 / 12
      elsif numOwned > 300
        c = x * 3 / 12
      else
        c = x * 2 / 12
      end
      if c > 0 && pbRandom(256) < c
        @criticalCapture = true
        return 4
      end
    end
    # Calculate the number of shakes
    numShakes = 0
    for i in 0...4
      break if numShakes < i
      numShakes += 1 if pbRandom(65536) < y
    end
    return numShakes
  end
end
